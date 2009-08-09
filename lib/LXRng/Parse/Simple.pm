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
	'pref'		=> '',
	'rest'		=> '',
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

    my $btype;
    my $pos = 0;
    while (1) {
	if (defined $btype) {
	    if ($$self{'rest'} =~ s/\A((?s:.*?)$$self{'term'}[$btype])//m) {
		my $ret = $$self{'pref'}.$1;
		$$self{'pref'} = '';
		return ($$self{'bodyid'}[$btype], $ret);
	    }
	    else {
		$$self{'pref'} .= $$self{'rest'};
		$$self{'rest'} = '';
	    }
	}
	else {
	    pos($$self{'rest'}) = $pos;
	    if ($$self{'rest'} =~ s/\G((?s).*?)($$self{'open'})//m) {
		my $pref = substr($$self{'rest'}, 0, $pos, '').$1;
		my $frag = $2;

		if ($pref ne '') {
		    $$self{'rest'} = $frag.$$self{'rest'};
		    return ('', $pref);
		}

		$btype = 3;
		$btype++ while $btype < $#- and !defined($-[$btype]);
		$btype -= 3;

		if (!defined($$self{'term'}[$btype])) {
		    # Opening regexp captures entire block.
		    return ($$self{'bodyid'}[$btype], $frag);
		}
		$$self{'pref'} = $frag;
	    }
	}

	my $line = $$self{'fileh'}->getline;
	unless (defined $line) {
	    my $ret = $$self{'pref'}.$$self{'rest'};
	    $$self{'pref'} = '';
	    $$self{'rest'} = '';
	    undef($ret) unless length($ret) > 0;
	    
	    return (defined($btype) ? $$self{'bodyid'}[$btype] : '', $ret);
	}

	if ($. <= 2 &&
	    $line =~ /^.*-[*]-.*?[ \t;]tab-width:[ \t]*([0-9]+).*-[*]-/) {
	    # make sure there really is a non-zero tabwidth
	    $$self{'tabwidth'} = $1 if $1 > 0;
	}
	    
	untabify($line, $$self{'tabwidth'});
	$pos = length($$self{'rest'});
	$$self{'rest'} .= $line;

	unless ($$self{'bofseen'}) {
	    # return start marker if file has contents
	    $$self{'bofseen'} = 1;
	    return ('start', '');
	}
    }
}

1;
