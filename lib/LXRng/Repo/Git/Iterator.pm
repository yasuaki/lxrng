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

package LXRng::Repo::Git::Iterator;

use strict;
use LXRng::Repo::Git::File;

sub new {
    my ($class, $repo, $release) = @_;

    my @refs;
    my $git = $repo->_git_cmd('ls-tree', '-r', $release);
    while (<$git>) {
	if (/\S+\s+blob\s+(\S+)\s+(\S+)/) {
	    push(@refs, [$2, $1]);
	}
    }
    close($git);

    return bless({refs => \@refs, repo => $repo, rel => $release}, $class);
}

sub next {
    my ($self) = @_;

    return undef unless @{$$self{'refs'}} > 0;
    my $file = shift(@{$$self{'refs'}});

    return LXRng::Repo::Git::File->new($$self{'repo'},
					  $$file[0],
					  $$file[1],
					  $$self{'rel'});
}

1;
