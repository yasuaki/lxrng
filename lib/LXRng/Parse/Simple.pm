# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no> and others.
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

package LXRng::Parse::Simple;

use strict;
use integer;
use IO::Handle;

sub new {
    my ($class, $fileh, $tabhint, @blksep) = @_;

    my (@bodyid, @open, @term);

    while (my @a = splice(@blksep,0,3)) {
	push(@bodyid, $a[0]);
	push(@open,   $a[1]);
	push(@term,   $a[2]);
    }

    my $self = {
	'fileh'		=> $fileh,	# File handle
	'tabwidth'	=> $tabhint||8,	# Tab width
	'frags'		=> [],		# Fragments in queue
	'bodyid'	=> \@bodyid,	# Array of body type ids
	'bofseen'	=> 0,		# Beginning-of-file seen?
	'term'		=> \@term,
					# Fragment closing delimiters
	'open'		=> join('|', map { "($_)" } @open),
					# Fragment opening regexp
	'split'		=> join('|', @open, map { $_ eq '' ? () : $_ } @term),
					# Fragmentation regexp
    };

    return bless $self, $class;
}

sub untabify {
    my $t = $_[1] || 8;

    $_[0] =~ s/^(\t+)/(' ' x ($t * length($1)))/ge; # Optimize for common case.
    $_[0] =~ s/([^\t]*)\t/$1.(' ' x ($t - (length($1) % $t)))/ge;
    return($_[0]);
}


sub nextfrag {
    my ($self) = @_;

    my $btype = undef;
    my $frag = undef;
    my $line = '';

    while (1) {
	# read one more line if we have processed 
	# all of the previously read line
	if (@{$$self{'frags'}} == 0) {
	    $line = $$self{'fileh'}->getline;
	    
	    if ($. <= 2 &&
		$line =~ /^.*-[*]-.*?[ \t;]tab-width:[ \t]*([0-9]+).*-[*]-/) {
		# make sure there really is a non-zero tabwidth
		$$self{'tabwidth'} = $1 if $1 > 0;
	    }
	    
	    if(defined($line)) {
		untabify($line, $$self{'tabwidth'});

		# split the line into fragments
		$$self{'frags'} = [split(/($$self{'split'})/, $line)];
	    }
	}

	last if @{$$self{'frags'}} == 0;

	unless ($$self{'bofseen'}) {
	    # return start marker if file has contents
	    $$self{'bofseen'} = 1;
	    return ('start', '');
	}
	
	# skip empty fragments
	if ($$self{'frags'}[0] eq '') {
	    shift(@{$$self{'frags'}});
	}

	# check if we are inside a fragment
	if (defined($frag)) {
	    if (defined($btype)) {
		my $next = shift(@{$$self{'frags'}});
		
		# Add to the fragment
		$frag .= $next;
		# We are done if this was the terminator
		last if $next =~ /^$$self{'term'}[$btype]$/;
		
	    }
	    else {
		if ($$self{'frags'}[0] =~ /^$$self{'open'}$/) {
		    last;
		}
		$frag .= shift(@{$$self{'frags'}});
	    }
	}
	else {
	    # Find the blocktype of the current block
	    $frag = shift(@{$$self{'frags'}});
	    if (defined($frag) && (@_ = $frag =~ /^$$self{'open'}$/)) {
		# grep in a scalar context returns the number of times
		# EXPR evaluates to true, which is this case will be
		# the index of the first defined element in @_.

		my $i = 1;
		$btype = grep { $i &&= !defined($_) } @_;
		if(!defined($$self{'term'}[$btype])) {
		    # Opening regexp captures entire block.
		    last;
		}
	    }
	}
    }
    $btype = $$self{'bodyid'}[$btype] if defined($btype);
    
    return ($btype, $frag);
}

1;
