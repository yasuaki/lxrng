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
