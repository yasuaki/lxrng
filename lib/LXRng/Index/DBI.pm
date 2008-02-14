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

package LXRng::Index::DBI;

use strict;
use DBI;

use base qw(LXRng::Index::Generic);

sub transaction {
    my ($self, $code) =  @_;
    if ($self->dbh->{AutoCommit}) {
	$self->dbh->{AutoCommit} = 0;
	$code->();
	$self->dbh->{AutoCommit} = 1;
    }
    else {
	# If we're in a transaction already, don't return to
	# AutoCommit state.
	$code->();
    }
    $self->dbh->commit() unless $self->dbh->{AutoCommit};
}

sub _to_task {
    my ($self, $rfile_id, $task) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_to_task_ins'} ||=
	$dbh->prepare(qq{insert into ${pre}filestatus(id_rfile)
			     select ? where not exists
			     (select 1 from ${pre}filestatus 
			      where id_rfile = ?)});
    $sth->execute($rfile_id, $rfile_id);

    $sth = $$self{'sth'}{'_to_task_upd'}{$task} ||=
	$dbh->prepare(qq{update ${pre}filestatus set $task = 't' 
			     where $task = 'f' and id_rfile = ?});
    return $sth->execute($rfile_id) > 0;
}

sub to_index {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'indexed');
}

sub to_reference {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'referenced');
}

sub to_hash {
    my ($self, $rfile_id) = @_;

    return $self->_to_task($rfile_id, 'hashed');
}

sub _get_tree {
    my ($self, $tree) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_tree'} ||=
	$dbh->prepare(qq{select id from ${pre}trees where name = ?});
    my $id;
    if ($sth->execute($tree) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub pending_files {
    my ($self, $tree) = @_;

    my $tree_id = $self->_get_tree($tree);
    return [] unless $tree_id;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;

    # Can be made more fine grained by consulting filestatus, but all
    # hashed documents need to have their termlist updated...  Just
    # include all files participating in releases not yet fully
    # indexed.
    my $sth = $$self{'sth'}{'pending_files'} ||=
	$dbh->prepare(qq{
	    select rv.id, f.path, rv.revision
		from ${pre}revisions rv, ${pre}files f
		where rv.id_file = f.id
		and rv.id in (select fr.id_rfile
			      from ${pre}releases r, ${pre}filereleases fr
			      where r.id = fr.id_release
			      and r.id_tree = ?
			      and r.is_indexed = 'f')});

    if ($sth->execute($tree_id) > 0) {
	return $sth->fetchall_arrayref();
    }
    else {
	$sth->finish();
	return [];
    }
}

sub new_releases_by_file {
    my ($self, $file_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'releases_by_file'} ||=
	$dbh->prepare(qq{
	    select r.release_tag from ${pre}releases r, ${pre}filereleases f
		where r.id = f.id_release and f.id_rfile = ? and r.is_indexed = 'f'});
    if ($sth->execute($file_id) > 0) {
	return [map { $$_[0] } @{$sth->fetchall_arrayref()}];
    }
    else {
	$sth->finish();
	return [];
    }
}

sub update_indexed_releases {
    my ($self, $tree) = @_;

    my $tree_id = $self->_get_tree($tree);
    return [] unless $tree_id;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'update_indexed_releases_find'} ||=
	$dbh->prepare(qq{
	    select r.id, r.release_tag
		from ${pre}releases r
		where is_indexed = 'f'
		and not exists (select 1
				from ${pre}filereleases fr
				left outer join ${pre}filestatus fs
				on (fr.id_rfile = fs.id_rfile)
				where fr.id_release = r.id
				and (fs.id_rfile is null
				     or fs.indexed = 'f'
				     or fs.hashed = 'f'
				     or fs.referenced = 'f'))});
    
    if ($sth->execute() > 0) {
	my $rels = $sth->fetchall_arrayref();
	$sth->finish();
	$sth = $$self{'sth'}{'update_indexed_releases_set'} ||=
	    $dbh->prepare(qq{
		update ${pre}releases set is_indexed = 't' where id = ?});
	foreach my $r (@$rels) {
	    $sth->execute($$r[0]);
	}
	$sth->finish();
	return [map { $$_[1] } @$rels];
    }
    else {
	return [];
    }
}

sub _get_release {
    my ($self, $tree_id, $release) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_release'} ||=
	$dbh->prepare(qq{select id from ${pre}releases
			     where id_tree = ? and release_tag = ?});
    my $id;
    if ($sth->execute($tree_id, $release) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_file {
    my ($self, $path) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_file'} ||=
	$dbh->prepare(qq{select id from ${pre}files where path = ?});
    my $id;
    if ($sth->execute($path) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_rfile_by_release {
    my ($self, $rel_id, $path) = @_;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_rfile_by_release'} ||=
	$dbh->prepare(qq{select r.id
			     from ${pre}filereleases fr, ${pre}files f,
			     ${pre}revisions r
			     where fr.id_rfile = r.id and r.id_file = f.id
			     and fr.id_release = ? and f.path = ?});

    my $id;
    if ($sth->execute($rel_id, $path) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}

sub _get_symbol {
    my ($self, $symbol) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_symbol'} ||=
	$dbh->prepare(qq{select id from ${pre}symbols where name = ?});
    my $id;
    if ($sth->execute($symbol) > 0) {
	($id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $id;
}


sub _add_include {
    my ($self, $file_id, $inc_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_include'} ||=
	$dbh->prepare(qq{insert into ${pre}includes(id_rfile, id_include_path)
			     values (?, ?)});
    my $id;
    $sth->execute($file_id, $inc_id);

    return 1;
}

sub _includes_by_id {
    my ($self, $file_id) = @_;

}

sub _symbol_by_id {
    my ($self, $id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_symbol_by_id'} ||=
	$dbh->prepare(qq{select * from ${pre}symbols
			     where id = ?});
    my @res;
    if ($sth->execute($id) > 0) {
	@res = $sth->fetchrow_array();
    }
    $sth->finish();

    return @res;
}

sub _identifiers_by_name {
    my ($self, $rel_id, $symbol) = @_;

    my $sym_id = $self->_get_symbol($symbol);
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_identifiers_by_name'} ||=
	$dbh->prepare(qq{
	    (select i.id, i.type, f.path, i.line, i.id_rfile
		from ${pre}identifiers i, ${pre}files f,
			 ${pre}filereleases r, ${pre}revisions v
		where i.id_rfile = v.id and v.id = r.id_rfile 
		and r.id_release = ? and v.id_file = f.id 
		and i.type != 'm' and i.type != 'l'
		and i.id_symbol = ? limit 250)
	    union
	    (select i.id, i.type, f.path, i.line, i.id_rfile
		from ${pre}identifiers i, ${pre}files f,
			 ${pre}filereleases r, ${pre}revisions v
		where i.id_rfile = v.id and v.id = r.id_rfile 
		and r.id_release = ? and v.id_file = f.id 
		and (i.type = 'm' or i.type = 'l')
		and i.id_symbol = ? limit 250)});

    $sth->execute($rel_id, $sym_id, $rel_id, $sym_id);
    my $res = $sth->fetchall_arrayref();

    return $res;
}

sub _symbols_by_file {
    my ($self, $rfile_id) = @_;
    
    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_symbols_by_file'} ||=
	$dbh->prepare(qq{select distinct s.name 
			     from ${pre}usage u, ${pre}symbols s
			     where id_rfile = ? and u.id_symbol = s.id});
    $sth->execute($rfile_id);
    my %res;
    while (my ($symname) = $sth->fetchrow_array()) {
	$res{$symname} = 1;
    }

    return \%res;
}

sub _usage_by_file {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_usage_by_file'} ||=
	$dbh->prepare(qq{select s.name, u.line
			     from ${pre}usage u, ${pre}symbols s
			     where id_rfile = ? and u.id_symbol = s.id});
    $sth->execute($rfile_id);

    die "Unimplemented";
}

sub _rfile_path_by_id {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_rfile_path_by_id'} ||=
	$dbh->prepare(qq{select f.path from ${pre}files f, ${pre}revisions r
			     where f.id = r.id_file and r.id = ?});
    my $path;
    if ($sth->execute($rfile_id) > 0) {
	($path) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $path;
}

sub _get_includes_by_file {
    my ($self, $res, $rel_id, @rfile_ids) = @_;

    my @recurse;
    while (@rfile_ids > 0) {
	my @rfile_batch = splice(@rfile_ids, 0, 8192);

	my $dbh = $self->dbh;
	my $pre = $self->prefix;
	my $sth;

	$sth = $$self{'sth'}{'get_includes_by_file'} if
	    @rfile_batch == 1024;

	unless ($sth) {
	    my $placeholders = join(', ', ('?') x @rfile_batch);
	    $sth = $dbh->prepare(qq{select rf.id, f.path 
					from ${pre}revisions rf,
					${pre}filereleases v,
					${pre}includes i,
					${pre}revisions ri,
					${pre}files f
					where rf.id = i.id_rfile
					and rf.id_file = f.id
					and rf.id = v.id_rfile
					and v.id_release = ?
					and i.id_include_path = ri.id_file
					and ri.id in ($placeholders)});

	    $$self{'sth'}{'get_includes_by_file'} = $sth if
		@rfile_batch == 8192;
	}

	$sth->execute($rel_id, @rfile_batch);
	my $files = $sth->fetchall_arrayref();
	$sth->finish();

	foreach my $r (@$files) {
	    push(@recurse, $$r[0]) unless exists($$res{$$r[0]});

	    $$res{$$r[0]} = $$r[1];
	}
    }
    $self->_get_includes_by_file($res, $rel_id, @recurse) if @recurse;

    return 1;
}

sub add_hashed_document {
    my ($self, $rfile_id, $doc_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'add_hashed_document'} ||=
	$dbh->prepare(qq{insert into ${pre}hashed_documents(id_rfile, doc_id)
			     values (?, ?)});
    $sth->execute($rfile_id, $doc_id);

    return 1;
}

sub get_hashed_document {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_hashed_document'} ||=
	$dbh->prepare(qq{select doc_id from ${pre}hashed_documents
			     where id_rfile = ?});
    my $doc_id;
    if ($sth->execute($rfile_id) > 0) {
	($doc_id) = $sth->fetchrow_array();
    }
    $sth->finish();

    return $doc_id;
}

sub get_symbol_usage {
    my ($self, $rel_id, $symid) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;

    # Postgres' query optimizer deals badly with placeholders and
    # prepared statements in this case.
    return undef unless $symid =~ /^\d+$/s;
    my $sth =
	$dbh->prepare(qq{
	    select f.path, u.lines
		from ${pre}usage u, ${pre}filereleases fr,
			${pre}files f, ${pre}revisions r
		where u.id_symbol = $symid
		and u.id_rfile = fr.id_rfile and fr.id_release = ?
		and u.id_rfile = r.id and r.id_file = f.id
		limit 1000});

    $sth->execute($rel_id);
    my $res = $sth->fetchall_arrayref();
    $sth->finish();

    my %rlines;
    foreach my $r (@$res) {
	$rlines{$$r[0]} = [$$r[1] =~ /(\d+),?/g];
    }

    return \%rlines;
}

sub get_identifier_info {
    my ($self, $usage, $ident, $rel_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_identifier_info'} ||=
	$dbh->prepare(qq{
	    select s.name, s.id,
	    i.id, i.type, f.path, i.line, cs.name, c.type, c.id,
	    i.id_rfile
		from ${pre}identifiers i
	        left outer join ${pre}identifiers c on i.context = c.id
		left outer join ${pre}symbols cs on c.id_symbol = cs.id,
		${pre}symbols s, ${pre}revisions r, ${pre}files f
		where i.id = ? and i.id_symbol = s.id 
		and i.id_rfile = r.id and r.id_file = f.id});

    unless ($sth->execute($ident) == 1) {
	return undef;
    }

    my ($symname, $symid,
	$iid, $type, $path, $line, $cname, $ctype, $cid, $rfile_id) =
	    $sth->fetchrow_array();
    $sth->finish();

    my $incs = {$rfile_id => $path};
    $self->get_referring_files($rel_id, $rfile_id, $incs);
    my %paths; @paths{values %$incs} = ();

    my $refs = $usage->get_symbol_usage($rel_id, $symid);
    my %reflines;
    my ($p, $l);
    while (($p, $l) = each %$refs) {
	next unless exists $paths{$p};
	$reflines{$p} = $l;
    }

    return ($symname, $symid, 
	    [$iid, $type, $path, $line, $cname, $ctype, $cid, $rfile_id],
	    \%reflines);
}

sub get_rfile_timestamp {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'get_rfile_timestamp'} ||=
	$dbh->prepare(qq{
	    select extract(epoch from last_modified_gmt)::integer,
	    last_modified_tz
		from ${pre}revisions where id = ?});
    
    unless ($sth->execute($rfile_id) == 1) {
	return undef;
    }

    my ($epoch, $tz) = $sth->fetchrow_array();
    $sth->finish();

    return ($epoch, $tz);
}    

sub files_by_wildcard {
    my ($self, $tree, $release, $query) = @_;

    return [] unless $query =~ /[a-zA-Z0-9]/;
    
    my $rel_id = $self->release_id($tree, $release);
    return [] unless $rel_id;

    $query =~ tr/\?\*/_%/;
    unless ($query =~ s,^/,,) {
	# Absolute path queries are left alone, modulo leading-slash-removal.
	$query = '%'.$query.'%';
    }

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'files_by_wildcard'} ||=
	$dbh->prepare(qq{
	    select f.path
		from ${pre}files f, ${pre}revisions v, ${pre}filereleases r
		where f.path like ? and f.id = v.id_file and v.id = r.id_rfile
		and r.id_release = ?
		order by f.path});

    $sth->execute($query, $rel_id);
    my @res;
    while (my ($path) = $sth->fetchrow_array()) {
	push(@res, $path);
    }

    return \@res;
}

1;
