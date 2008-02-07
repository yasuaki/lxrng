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

package LXRng::Repo::Plain::Iterator;

use strict;
use LXRng::Repo::Plain;

sub new {
    my ($class, $dir) = @_;

    return bless({dir => $dir, stack => [], nodes => [$dir->contents]}, $class);
}

sub next {
    my ($self) = @_;

    while (@{$$self{'nodes'}} == 0) {
	return undef unless @{$$self{'stack'}};
	$$self{'nodes'} = pop(@{$$self{'stack'}});
    }
    
    my $node = shift(@{$$self{'nodes'}});
    if ($node->isa('LXRng::Repo::Directory')) {
	push(@{$$self{'stack'}}, $$self{'nodes'});
	$$self{'nodes'} = [$node->contents];
	return $self->next;
    }
    return $node;
}

1;
