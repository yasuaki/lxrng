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

package LXRng::Repo::Plain::Directory;

use strict;

use base qw(LXRng::Repo::Directory);

sub new {
    my ($class, $name, $path, $stat) = @_;

    $name =~ s,/*$,/,;
    $path =~ s,/*$,/,;
    return bless({name => $name, path => $path, stat => $stat}, $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'path'};
}

sub time {
    my ($self) = @_;

    return $$self{'stat'}[9];
}

sub size {
    my ($self) = @_;

    return '';
}

sub contents {
    my ($self) = @_;

    my (@dirs, @files);
    my ($dir, $node);
    my $prefix = $$self{'name'};
    $prefix =~ s,^/+,,;
    opendir($dir, $$self{'path'}) or die("Can't open ".$$self{'path'}.": $!");
    while (defined($node = readdir($dir))) {
	next if $node =~ /^\.|~$|\.orig$/;
	next if $node eq 'CVS';
	
	my $file = LXRng::Repo::Plain::File->new($prefix.$node,
						 $$self{'path'}.$node);
	push(@files, $file) if $file;
    }
    closedir($dir);

    return sort { ref($a) cmp ref($b) || $$a{'name'} cmp $$b{'name'} } @files;
}

1;
