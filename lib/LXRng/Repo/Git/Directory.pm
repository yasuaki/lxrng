package LXRng::Repo::Git::Directory;

use strict;

use base qw(LXRng::Repo::Directory);

sub new {
    my ($class, $repo, $name, $ref, $rel) = @_;

    $name =~ s,/*$,/,;
    return bless({repo => $repo, name => $name, ref => $ref, rel => $rel},
		 $class);
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
	my ($mode, $type, $ref, $node) = split(" ", $_);
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
