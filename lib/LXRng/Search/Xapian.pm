package LXRng::Search::Xapian;

use strict;
use Search::Xapian qw/:ops :db :qpstem/;
use Search::Xapian::QueryParser;


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

sub add_document {
    my ($self, $doc, $rel_ids) = @_;
   
    foreach my $r (@$rel_ids) {
	$doc->add_term('__@@LXRREL_'.$r);
    }
    my $doc_id = $self->wrdb->add_document($doc);
    $self->{'writes'}++;
    $self->flush() if $self->{'writes'} % 499 == 0;
    return $doc_id;
}

sub add_release {
    my ($self, $doc_id, $rel_ids) = @_;

    my $doc = $self->wrdb->get_document($doc_id);

    my $termend = $doc->termlist_end;
    my $changes = 0;
    foreach my $r (@$rel_ids) {
	my $reltag = '__@@LXRREL_'.$r;
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
	$query =~ s/([\S_]+_[\S_]*)/\"$1\"/g;
	$query =~ s/_/ /g;
	$query =~ s/\b(?![A-Z][^A-Z]*\b)(\S+)/\L$1\E/g;
    }

    my $query = $qp->parse_query($query);
    $query = Search::Xapian::Query
	->new(OP_FILTER, $query, 
	      Search::Xapian::Query->new('__@@LXRREL_'.$rel_id));

    my $enq = $db->enquire($query);

    my $matches = $enq->get_mset(0, 100);
    my $total = $matches->get_matches_estimated();
    my $size = $matches->size();

    my @res;

    my $match = $matches->begin();
    my $i = 0;
    while ($i++ < $size) {
	my $term = $enq->get_matching_terms_begin($match);
	my $termend = $enq->get_matching_terms_end($match);
	my %lines;
	my $hits = 0;
	while ($term ne $termend) {
	    if ($term !~ /^__\@\@LXR/) {
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
