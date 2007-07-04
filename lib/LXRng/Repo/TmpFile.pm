package LXRng::Repo::TmpFile;

# This package is used to hold on to a reference to a physical copy of
# a file normally only present inside a repo of some sort.  When it
# leaves scopy, the destructor will remove it.  (The object acts as
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
