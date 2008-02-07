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

package LXRng::Index::Generic;

use strict;
use Memoize;


sub new {
    my ($class, %args) = @_;

    memoize('tree_id');
    memoize('release_id');

    return bless(\%args, $class);
}

sub prefix {
    my ($self) = @_;
    if (exists $$self{'table_prefix'}) {
	return $$self{'table_prefix'}.'_';
    }
    else {
	return '';
    }
}

sub tree_id {
    my ($self, $tree, $update) = @_;

    return $self->_get_tree($tree) ||
	($update ? $self->_add_tree($tree) : undef);
}

sub release_id {
    my ($self, $tree, $release, $update) = @_;

    my $tree_id = $self->tree_id($tree, $update);

    return $self->_get_release($tree_id, $release) ||
	($update ? $self->_add_release($tree_id, $release) : undef);
}

sub file_id {
    my ($self, $path, $update) = @_;

    return $self->_get_file($path) ||
	($update ? $self->_add_file($path) : undef);
}

sub rfile_id {
    my ($self, $node, $update) = @_;

    my $path = $node->name;
    my $revision = $node->revision;

    my $file_id = $self->file_id($path, $update);
    return undef unless $file_id;

    my ($id, $old_stamp) = $self->_get_rfile($file_id, $revision);
    return $id unless $update;

    if ($id) {
	my ($new_stamp) = $node->time =~ /^(\d+)/;
	if ($update and $old_stamp > $new_stamp) {
	    $self->_update_rfile_timestamp($id, $node->time);
	}
    }
    else {
	$id = $self->_add_rfile($file_id, $revision, $node->time);
    }
    return $id;
}

sub symbol_id {
    my ($self, $symbol, $update) = @_;

    return $self->_get_symbol($symbol) ||
	($update ? $self->_add_symbol($symbol) : undef);
}

sub add_filerelease {
    my ($self, $tree, $release, $rfile_id) = @_;

    my $rel_id = $self->release_id($tree, $release, 1);

    $self->_add_filerelease($rfile_id, $rel_id);
}

sub add_include {
    my ($self, $file_id, $include_path) = @_;

    my $inc_id = $self->_get_file($include_path);

    return 0 unless $inc_id;
    return $self->_add_include($file_id, $inc_id);
}

sub includes_by_file {
    my ($self, $tree, $release, $path) = @_;

    my $file_id = $self->file_id($tree, $release, $path);

    return $self->_includes_by_id($file_id);
}

sub add_ident {
    my ($self, $rfile_id, $line, $symbol, $type, $ctx_id) = @_;
    
    my $sym_id = $self->symbol_id($symbol, 1);

    return $self->_add_ident($rfile_id, $line, $sym_id, $type, $ctx_id);
}

sub symbol_by_id {
    my ($self, $id) = @_;
    
    return $self->_symbol_by_id($id);
}

sub identifiers_by_name {
    my ($self, $tree, $release, $symbol) = @_;

    my $rel_id = $self->release_id($tree, $release);

    return $self->_identifiers_by_name($rel_id, $symbol);
}

sub symbols_by_file {
    my ($self, $tree, $release, $path) = @_;

    $path =~ s!^/!!;
    my $rel_id = $self->_get_release($self->_get_tree($tree), $release);
    my $rfile_id = $self->_get_rfile_by_release($rel_id, $path);

    return $self->_symbols_by_file($rfile_id);
}

sub add_usage {
    my ($self, $doc, $file_id, $sym_id, $lines) = @_;

    return $self->_add_usage($file_id, $sym_id, $lines);
}

# TODO: What functionality actually uses this?  Can it be removed?
sub usage_by_file {
    my ($self, $tree, $release, $path) = @_;

    my $rel_id = $self->_get_release($self->_get_tree($tree), $release);
    my $rfile_id = $self->_get_rfile_by_release($rel_id, $path);
    
    return $self->_usage_by_file($rfile_id);
}

sub get_referring_files {
    my ($self, $rel_id, $rfile_id, $res) = @_;
    
    $res ||= {};
    $self->_get_includes_by_file($res, $rel_id, $rfile_id);
   
    return keys %$res;
}

1;
