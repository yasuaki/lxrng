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
