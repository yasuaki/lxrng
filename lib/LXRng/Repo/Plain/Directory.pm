package LXRng::Repo::Plain::Directory;

use strict;

use base qw(LXRng::Repo::Directory);

sub new {
    my ($class, $name, $path, $stat) = @_;

    $name =~ s,(.)/*$,$1/,;
    $path =~ s,/*$,/,;
    return bless({name => $name, path => $path, stat => $stat}, $class);
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
    opendir($dir, $$self{'path'}) or die("Can't open ".$$self{'path'}.": $!");
    while (defined($node = readdir($dir))) {
	next if $node =~ /^\.|~$|\.orig$/;
	next if $node eq 'CVS';
	
	push(@files, LXRng::Repo::Plain::File->new($$self{'name'}.$node,
						      $$self{'path'}.$node));
    }
    closedir($dir);

    return sort { ref($a) cmp ref($b) || $$a{'name'} cmp $$b{'name'} } @files;
}

1;
