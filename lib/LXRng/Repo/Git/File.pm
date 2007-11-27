package LXRng::Repo::Git::File;

use strict;

use base qw(LXRng::Repo::File);
use LXRng::Repo::TmpFile;
use File::Temp qw(tempdir);

sub new {
    my ($class, $repo, $name, $ref, $rel) = @_;

    return bless({repo => $repo, name => $name, ref => $ref, rel => $rel},
		 $class);
}

sub time {
    my ($self) = @_;

    if ($$self{'repo'}->_use_author_timestamp) {
	# This is painfully slow.  It is only performed index-time,
	# but that might stil be bad enough that you would want to
	# just use the release-timestamp insted.
	my $cinfo = $$self{'repo'}->_git_cmd('log', '--pretty=raw',
					     '--max-count=1', '--all',
					     '..'.$$self{'rel'},
					     '--', $self->name);

	my $time;
	while (<$cinfo>) {
	    $time = $1 if /^author .*? (\d+(?: [-+]\d+|))$/ ;
	    $time ||= $1 if /^committer .*? (\d+(?: [-+]\d+|))$/ ;
	}

	return $time if $time;
    }

    return $$self{'repo'}->_release_timestamp($$self{'rel'});
}

sub size {
    my ($self) = @_;

    my $git = $$self{'repo'}->_git_cmd('cat-file', '-s', $$self{'ref'});
    my $size = <$git>;
    close($git);
    chomp($size);
    return $size;
}

sub handle {
    my ($self) = @_;

    return $$self{'repo'}->_git_cmd('cat-file', 'blob', $$self{'ref'});
}

sub revision {
    my ($self) = @_;

    return $$self{'ref'};
}

sub phys_path {
    my ($self) = @_;

    return $$self{'phys_path'} if exists $$self{'phys_path'};

    my $tmpdir = tempdir() or die($!);
    open(my $phys, ">", $tmpdir.'/'.$self->node) or die($!);

    my $handle = $self->handle();
    my $buf = '';
    while (sysread($handle, $buf, 64*1024) > 0) {
	print($phys $buf) or die($!);
    }
    close($handle);
    close($phys) or die($!);
    
    return $$self{'phys_path'} = 
	LXRng::Repo::TmpFile->new(dir => $tmpdir,
				  node => $self->node);
}

1;
