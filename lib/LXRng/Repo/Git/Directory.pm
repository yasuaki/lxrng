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

package LXRng::Repo::Git::Directory;

use strict;

use base qw(LXRng::Repo::Directory);

sub new {
    my ($class, $repo, $name, $ref, $rel) = @_;

    $name =~ s,/*$,/,;
    return bless({repo => $repo, name => $name, ref => $ref, rel => $rel},
		 $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'repo'}->cache_key.":".$$self{'ref'};
}

sub time {
    my ($self) = @_;

    return 0;
#    return $$self{'stat'}[9];
}

sub size {
    my ($self) = @_;

    return '';
}

sub contents {
    my ($self) = @_;

    my $git = $$self{'repo'}->_git_cmd('ls-tree', $$self{'ref'});

    my $prefix = $$self{'name'};
    $prefix =~ s,^/+,,;
    my (@dirs, @files);
    while (<$git>) {
	chomp;
	my ($mode, $type, $ref, $node) = split(" ", $_, 4);
	if ($type eq 'tree') {
	    push(@dirs, LXRng::Repo::Git::Directory->new($$self{'repo'},
							    $prefix.$node,
							    $ref,
							    $$self{'rel'}));
	}
	elsif ($type eq 'blob') {
	    push(@files, LXRng::Repo::Git::File->new($$self{'repo'},
							$prefix.$node,
							$ref,
							$$self{'rel'}));
	}
    }

    return (@dirs, @files);
}

1;
