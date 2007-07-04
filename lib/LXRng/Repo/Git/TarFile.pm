package LXRng::Repo::Git::TarFile;

use strict;
use File::Temp qw(tempdir);
use Fcntl qw(F_GETFD F_SETFD FD_CLOEXEC);

use base qw(LXRng::Repo::File);

sub new {
    my ($class, $tar, $ref) = @_;

    return bless({tar => $tar, ref => $ref}, $class);
}

sub name {
    my ($self) = @_;

    return $$self{'tar'}->name();
}

sub node {
    my ($self) = @_;

    $self->name =~ m,.*/([^/]+), and return $1;
}

sub time {
    my ($self) = @_;

    return $$self{'tar'}->mtime();
}

sub size {
    my ($self) = @_;

    return $$self{'tar'}->size;
}

sub phys_path {
    my ($self) = @_;

    my $tmpdir = tempdir() or die($!);
    open(my $phys, ">", $tmpdir.'/'.$self->node);

    my $data = $$self{'tar'}->get_content_by_ref();
    my $len = $$self{'tar'}->size();
    my $pos = 0;
    while ($pos < $len) {
	print($phys substr($$data, $pos, 64*1024));
	$pos += 64*1024;
    }
    close($phys);
    
    return LXRng::Repo::Git::TarFile::Virtual->new(dir => $tmpdir,
						      node => $self->node);
}

sub handle {
    my ($self) = @_;
    
    my $data = $$self{'tar'}->get_content_by_ref();
    open(my $fh, "<", $data);

    return $fh;
}

sub revision {
    my ($self) = @_;

    $$self{'ref'} ||= $self->time.'.'.$self->size;
    return $$self{'ref'};
}

package LXRng::Repo::Git::TarFile::Virtual;

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
#    kill(9, $$self{'pid'});
}

1;
