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

package LXRng::Markup::Dir;

use strict;
use POSIX qw(strftime);
use LXRng::Cached;

sub new {
    my ($class, %args) = @_;

    return bless(\%args, $class);
}

sub context {
    my ($self) = @_;
    return $$self{'context'};
}

sub _format_time {
    my ($secs, $zone) = @_;

    my $offset = 0;
    if ($zone and $zone =~ /^([-+])(\d\d)(\d\d)$/) {
	$offset = ($2 * 60 + $3) * 60;
	$offset = -$offset if $1 eq '-';
	$secs += $offset;
    }
    else {
	$zone = '';
    }
    return strftime("%F %T $zone", gmtime($secs));
}

sub listing {
    my ($self) = @_;

    cached {
	my @list;
	foreach my $n ($$self{'node'}->contents) {
	    if ($n->isa('LXRng::Repo::Directory')) {
		push(@list, {'name' => $n->name,
			     'node' => $n->node,
			     'size' => '',
			     'time' => '',
			     'desc' => ''});
	    }
	    else {
		my $rfile_id = $self->context->config->{'index'}->rfile_id($n);
		my ($s, $tz) = 
		    $self->context->config->{'index'}->get_rfile_timestamp($rfile_id);
		($s, $tz) = $n->time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/
		    unless $s;
		
		push(@list, {'name' => $n->name,
			     'node' => $n->node,
			     'size' => $n->size,
			     'time' => _format_time($s, $tz),
			     'desc' => ''});
	    }
	}
	\@list;
    } $$self{'node'}->cache_key;
}

1;
