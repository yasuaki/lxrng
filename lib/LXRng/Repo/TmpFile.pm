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

package LXRng::Repo::TmpFile;

# This package is used to hold on to a reference to a physical copy of
# a file normally only present inside a repo of some sort.  When it
# leaves scopy, the destructor will remove it.  (The object acts as a
# string containing the path of the physical manifestation of the
# file.)

use strict;
use overload '""' => \&filename;

sub new {
    my ($class, %args) = @_;
    
    return bless(\%args, $class);
}

sub filename {
    my ($self) = @_;

    return $$self{'dir'}.'/'.$$self{'node'};
}

sub DESTROY {
    my ($self) = @_;
    unlink($$self{'dir'}.'/'.$$self{'node'});
    rmdir($$self{'dir'});
}

1;
