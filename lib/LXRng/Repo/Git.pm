package LXRng::Repo::Git;

use strict;
use Memoize;
use LXRng::Cached;
use LXRng::Repo::Git::Iterator;
use LXRng::Repo::Git::File;
use LXRng::Repo::Git::Directory;

sub _git_cmd {
    my ($self, $cmd, @args) = @_;

    my $git;
    my $pid = open($git, "-|");
    die $! unless defined $pid;
    if ($pid == 0) {
	$ENV{'GIT_DIR'} = $$self{'root'};
	exec('git', $cmd, @args);
	warn $!;
	kill(9, $$);
    }
    return $git;
}

sub new {
    my ($class, $root, %args) = @_;

    memoize('_release_timestamp');

    return bless({root => $root, %args}, $class);
}

sub _release_timestamp {
    my ($self, $release) = @_;

    my $cinfo = $self->_git_cmd('cat-file', 'commit', $release);

    my $time;
    while (<$cinfo>) {
	$time = $1 if /^author .*? (\d+(?: [-+]\d+|))$/ ;
	$time ||= $1 if /^committer .*? (\d+(?: [-+]\d+|))$/ ;
    }
    
    return $time;
}

sub _use_author_timestamp {
    my ($self) = @_;

    return $$self{'author_timestamp'};
}

sub _sort_key {
    my ($v) = @_;

    $v =~ s/(\d+)/sprintf("%05d", $1)/ge;
    return $v;
}

sub allversions {
    my ($self) = @_;

    cached {
	my @tags;
	my $tags = $self->_git_cmd('tag', '-l');
	while (<$tags>) {
	    chomp;
	    next if $$self{'release_re'} and $_ !~ $$self{'release_re'};
	    push(@tags, $_);
	}

	return (sort {_sort_key($b) cmp _sort_key($a) } @tags);
    };
}

sub node {
    my ($self, $path, $release) = @_;

    $path =~ s,^/+,,;
    $path =~ s,/+$,,;

    if ($path eq '') {
	open(my $tag, '<', $$self{'root'}.'/refs/tags/'.$release)
	    or return undef;
	my $ref = <$tag>;
	close($tag);
	chomp($ref);
	return LXRng::Repo::Git::Directory->new($self, '', $ref);
    }

    my $git = $self->_git_cmd('ls-tree', $release, $path);
    my ($mode, $type, $ref, $gitpath) = split(" ", <$git>);

    if ($type eq 'tree') {
	return LXRng::Repo::Git::Directory->new($self, $path, $ref, $release);
    }
    elsif ($type eq 'blob') {
	return LXRng::Repo::Git::File->new($self, $path, $ref, $release);
    }
    else {
	return undef;
    }
}

sub iterator {
    my ($self, $release) = @_;

    return LXRng::Repo::Git::Iterator->new($self, $release);
}

1;
