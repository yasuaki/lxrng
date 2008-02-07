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

package LXRng::Repo::Plain;

use strict;
use LXRng::Repo::Plain::Iterator;
use LXRng::Repo::Plain::File;
use LXRng::Repo::Plain::Directory;

sub new {
    my ($class, $root) = @_;

    $root .= '/' unless $root =~ /\/$/;
    return bless({root => $root}, $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'root'};
}

sub allversions {
    my ($self) = @_;

    my @ver = (sort { $b cmp $a }
	       grep { $_ ne "." and $_ ne ".." } 
	       map { substr($_, length($$self{'root'})) =~ /([^\/]*)/; $1 }
	       glob($$self{'root'}."*/"));

    return @ver;
}

sub node {
    my ($self, $path, $release) = @_;

    my $realpath = join('/', $$self{'root'}, $release, $path);
    return LXRng::Repo::Plain::File->new($path, $realpath);
}

sub iterator {
    my ($self, $release) = @_;

    return LXRng::Repo::Plain::Iterator->new($self->node('', $release));
}

1;
