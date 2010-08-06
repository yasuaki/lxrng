# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::Search::Xapian;

use strict;
use Search::Xapian qw/:ops :db :qpstem/;
use Search::Xapian::QueryParser;

our @STOPWORDS = qw(our ours you your yours him his she her hers they
                    them their theirs what which who whom this that
                    these those are was were been being have has had
                    having does did doing would should could the and
                    but for with all any);
our %STOPWORD = map { $_ => 1 } @STOPWORDS;


sub new {
    my ($class, $db_root) = @_;

    $ENV{'XAPIAN_PREFER_FLINT'} = 1;
    my $self = bless({'db_root' => $db_root,
		      'writes' => 0},
		     $class);
    
    return $self;
}

sub wrdb {
    my ($self) = @_;

    return $$self{'wrdb'} if $$self{'wrdb'};

    $$self{'wrdb_pid'} = $$;

    return $$self{'wrdb'} = Search::Xapian::WritableDatabase
	->new($$self{'db_root'}, Search::Xapian::DB_CREATE_OR_OPEN);
}

sub new_document {
    my ($self, $desc) = @_;

    my $doc = Search::Xapian::Document->new();
    $doc->set_data($desc);
    return $doc;
}

sub get_document {
    my ($self, $doc_id) = @_;

    return $self->wrdb->get_document($doc_id);
}

sub save_document {
    my ($self, $doc_id, $doc) = @_;

    return $self->wrdb->replace_document($doc_id, $doc);
}

sub add_document {
    my ($self, $doc, $rel_ids) = @_;
   
    foreach my $r (@$rel_ids) {
	$doc->add_term('__@@rel_'.$r);
    }
    my $doc_id = $self->wrdb->add_document($doc);
    $self->{'writes'}++;
    $self->flush() if $self->{'writes'} % 3271 == 0;
    return $doc_id;
}

sub add_release {
    my ($self, $doc_id, $rel_ids) = @_;

    my $doc = $self->wrdb->get_document($doc_id);

    my $termend = $doc->termlist_end;
    my $changes = 0;
    foreach my $r (@$rel_ids) {
	my $reltag = '__@@rel_'.$r;
	my $term = $doc->termlist_begin;
	$term->skip_to($reltag);
	if ($term ne $termend) {
	    next if $term->get_termname eq $reltag;
	}
	$doc->add_term($reltag);
	$changes++;
    }

    $self->wrdb->replace_document($doc_id, $doc) if $changes;
    return $changes;
}

sub indexed_term {
    my ($term) = @_;

    return 0 if length($term) <= 2;
    return 0 if length($term) > 128;
    return 0 if $STOPWORD{$term};
    
    return 1;
}

sub make_add_text {
    my ($index, $doc) = @_;

    return sub {
	my ($pos, $text) = @_;

	foreach my $term ($text =~ /(_*\w[\w_]*)/g) {
	    $term = lc($term);
	    next unless indexed_term($term);

	    $doc->add_posting($term, $pos++);
	    if ($term =~ /_/) {
		foreach my $subt ($term =~ /([^_]+)/g) {
		    next unless indexed_term($subt);
		    $doc->add_posting($subt, $pos++);
		}
	    }
	};
    }
}

sub flush {
    my ($self) = @_;

    warn "*** hash: flushing\n";
    $self->wrdb->flush();
}

sub search {
    my ($self, $rel_id, $query) = @_;

    my $db = Search::Xapian::Database->new($$self{'db_root'});
    my $qp = new Search::Xapian::QueryParser($db);
    $qp->set_stemming_strategy(STEM_NONE);
    $qp->set_default_op(OP_AND);

    if ($query =~ /\"/) {
	# Only moderate fixup of advanced queries
	$query =~ s/\b([A-Z]+)\b/\L$1\E/g;
    }
    else {
	$query =~ s/([\S_]+_[\S_]*)/"\"$1\""/ge;
	$query =~ s/\b(?![A-Z][^A-Z]*\b)(\S+)/\L$1\E/g;
    }
    $query =~ s/\b([+]?(\w+))\b/indexed_term($2) ? $1 : ""/ge;

    my $parsed = $qp->parse_query($query);
    $parsed = Search::Xapian::Query
	->new(OP_FILTER, $parsed, 
	      Search::Xapian::Query->new('__@@rel_'.$rel_id));

    my $enq = $db->enquire($parsed);

    my $matches = $enq->get_mset(0, 100);
    my $total = $matches->get_matches_estimated();
    my $size = $matches->size();

    if ($size == 0 and $query =~ /_/) {
	# Retry with underscores replaced with spaces, to capture
	# partial matches.  Not particularly elegant, but searching
	# for both variants simultaneously is more work for Xapian
	# than doing it in sequence.
	$query =~ s/_/ /g;
	$query =~ s/\b([+]?(\w+))\b/indexed_term($2) ? $1 : ""/ge;

	$parsed = $qp->parse_query($query);
	$parsed = Search::Xapian::Query
	    ->new(OP_FILTER, $parsed, 
		  Search::Xapian::Query->new('__@@rel_'.$rel_id));

	$enq = $db->enquire($parsed);

	$matches = $enq->get_mset(0, 100);
	$total = $matches->get_matches_estimated();
	$size = $matches->size();
    }

    my @res;

    my $match = $matches->begin();
    my $i = 0;
    while ($i++ < $size) {
	my $term = $enq->get_matching_terms_begin($match);
	my $termend = $enq->get_matching_terms_end($match);
	my %lines;
	my $hits = 0;
	while ($term ne $termend) {
	    if ($term !~ /^__\@\@rel/) {
		my $pos = $db->positionlist_begin($match->get_docid(), $term);
		my $posend = $db->positionlist_end($match->get_docid(), $term);
		while ($pos ne $posend) {
		    $lines{int($pos/100)}{$term} = 1;
		    $hits++;
		    $pos++;
		}
	    }
	    $term++;
	}
	# Sort lines in order of the most matching terms
	my %byhits;
	foreach my $l (keys %lines) {
	    $byhits{0+keys(%{$lines{$l}})}{$l} = 1;
	}
	# Only consider the lines having the max number of terms
	my ($max) = sort { $b <=> $a } keys %byhits;
	my @lines = sort keys(%{$byhits{$max}});

	push(@res, [$match->get_percent(),
		    $match->get_document->get_data(),
		    $lines[0],
		    0+@lines])
	    if @lines;
	$match++;
    }

    return ($total, \@res);
}

sub add_usage {
    my ($self, $doc, $file_id, $sym_id, $lines) = @_;

    my $term = '__@@sym_'.$sym_id;
    foreach my $line (@$lines) {
	$doc->add_posting($term, $line);
    }
}

sub get_symbol_usage {
    my ($self, $rel_id, $sym_id) = @_;

    my $db = Search::Xapian::Database->new($$self{'db_root'});
    my $query = Search::Xapian::Query
	->new(OP_FILTER,
	      Search::Xapian::Query->new('__@@sym_'.$sym_id),
	      Search::Xapian::Query->new('__@@rel_'.$rel_id));

    my $enq = $db->enquire($query);

    my $matches = $enq->get_mset(0, 1000);
    my $total = $matches->get_matches_estimated();
    my $size = $matches->size();

    my %res;

    my $match = $matches->begin();
    my $i = 0;
    my $lines = 0;

  match:
    while ($i++ < $size) {
	my $term = $enq->get_matching_terms_begin($match);
	my $termend = $enq->get_matching_terms_end($match);

	while ($term ne $termend) {
	    if ($term !~ /^__\@\@rel/) {
		my $pos = $db->positionlist_begin($match->get_docid(), $term);
		my $posend = $db->positionlist_end($match->get_docid(), $term);
		while ($pos ne $posend) {
		    $res{$match->get_document->get_data()}{0+$pos} = 1;
		    $pos++;
		    last match if $lines++ > 1000;
		}
	    }
	    $term++;
	}
	$match++;
    }

    foreach my $r (keys %res) {
	$res{$r} = [sort { $a <=> $b } keys %{$res{$r}}];
    }
    return \%res;
}


sub reset_db {
    my ($self) = @_;

    foreach my $f (glob($$self{'db_root'}.'/*')) {
	unlink($f);
    }
}

sub DESTROY {
    my ($self) = @_;
   
    if ($self->{'writes'} > 0) {
	if ($$self{'wrdb_pid'} != $$) {
	    undef $$self{'wrdb'};
	}
	else {
	    $self->flush();
	}
    }
}

1;
