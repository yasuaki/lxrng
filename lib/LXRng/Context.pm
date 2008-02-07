package LXRng::Context;

use strict;
use LXRng;

sub new {
    my ($self, %args) = @_;

    $self = bless({}, $self);

    my $config = $self->read_config();

    if ($args{'query'}) {
	# Argle.  Both CGI and CGI::Simple seem to botch this up, in
	# different ways.  CGI breaks if SCRIPT_NAME contains regex
	# metachars, and CGI::Simple does funny things if SCRIPT_NAME
	# is the empty string.  Do it by hand...
	my $host = 'http'.($ENV{'HTTPS'} eq 'ON' ? 's' : '').'://'.
	    $ENV{'SERVER_NAME'}.
	    ($ENV{'SERVER_PORT'} == ($ENV{'HTTPS'} eq 'ON' ? 443 : 80)
	     ? '' : ':'.$ENV{'SERVER_PORT'});
	my $path = $ENV{'REQUEST_URI'};
	$path =~ s/\?.*//;
	$path =~ s,/+,/,g;
	$$self{'req_url'} = $host.$path;

	foreach my $p ($args{'query'}->param) {
	    $$self{'params'}{$p} = [$args{'query'}->param($p)];
	}
	my @prefs = $args{'query'}->cookie('lxr_prefs');
	if (@prefs) {
	    $$self{'prefs'} = { 
		map { /^(.*?)(?:=(.*)|)$/; ($1 => $2) } @prefs };
	}
	foreach my $tree (keys %$config) {
	    my $base = $$config{$tree}{'base_url'};
	    $base =~ s,^https?://[^/]+,,;
	    $base =~ s,/*$,/,;

	    if ($path =~ m,^\Q$base\E(\Q$tree\E|)([+][^/]+|)(?:$|/)(.*),) {
		@$self{'tree', 'path'} = ($1.$2, $3);
		last;
	    }
	}

	$$self{'tree'} = $args{'query'}->param('tree') 
	    if $args{'query'}->param('tree');
    }
    if ($args{'tree'}) {
	$$self{'tree'} = $args{'tree'};
    }

    if ($$self{'tree'} =~ s/[+]([^+]*)$//) {
	$$self{'release'} = $1 if $1 ne '*';
    }

    if ($$self{'tree'} and $$self{'tree'} !~ /^[+]/) {
	my $tree = $$self{'tree'};
	die("No config for tree $tree") 
	    unless exists($$config{$tree});

	$$self{'config'} = $$config{$tree};
	$$self{'config'}{'usage'} ||= $$self{'config'}{'index'};
    }

    if (exists $$self{'params'}{'v'} and $$self{'params'}{'v'}) {
	$$self{'release'} ||= $$self{'params'}{'v'}[0];
	delete($$self{'params'}{'v'});
    }

    if ($$self{'config'}) {
	$$self{'release'} ||= $$self{'config'}{'ver_default'};
	$$self{'release'} ||= $$self{'config'}{'ver_list'}[0];
    }

    return $self;
}

sub read_config {
    my ($self) = @_;

    my $confpath = $LXRng::ROOT.'/lxrng.conf';

    if (open(my $cfgfile, $confpath)) {
	my @config = eval("use strict; use warnings;\n".
			  "#line 1 \"configuration file\"\n".
			  join("", <$cfgfile>));
	die($@) if $@;

	die("Bad configuration file format\n")
	    unless @config == 1 and ref($config[0]) eq 'HASH';
	return $config[0];
    }
    else {
	die("Couldn't open configuration file \"$confpath\".");
    }
}

sub release {
    my ($self, $value) = @_;

    $$self{'release'} = $value if @_ == 2;
    return $$self{'release'};
}

sub default_release {
    my ($self, $value) = @_;

    return $$self{'config'}{'ver_default'};
}

sub all_releases {
    my ($self) = @_;

    return $$self{'config'}{'ver_list'};
}

sub param {
    my ($self, $key) = @_;
    my @res;

    @res = @{$$self{'params'}{$key}} if
	exists $$self{'params'}{$key};

    return wantarray ? @res : $res[0];
}

sub path {
    my ($self, $value) = @_;

    $$self{'path'} = $value if @_ == 2;
    return $$self{'path'};
}

sub tree {
    my ($self) = @_;

    return $$self{'tree'};
}

sub vtree {
    my ($self) = @_;

    if ($self->release ne $self->default_release) {
	return $self->tree.'+'.$self->release;
    }
    else {
	return $self->tree;
    }
}

sub path_elements {
    my ($self) = @_;

    return [] if $self->path =~ /^[ +]/;

    my @path;
    return [map {
	push(@path, $_); { 'node' => $_, 'path' => join('', @path) }
    } $self->path =~ m,([^/]+\/?),g];
}

sub config {
    my ($self) = @_;

    return $$self{'config'} || {};
}

sub prefs {
    my ($self) = @_;

    return $$self{'prefs'};
}

sub base_url {
    my ($self, $notree) = @_;

    my $base = $self->config->{'base_url'};
    unless ($base) {
	$base = $$self{'req_url'};
    }

    $base =~ s,/*$,/,;

    return $base if $notree;

    $base .= $self->vtree.'/';
    $base =~ s,/+$,/,;

    return $base;
}

sub args_url {
    my ($self, %args) = @_;

    # Todo: escape
    my $args = join(';', map { $_.'='.$args{$_} } keys %args);
    $args = '?'.$args if $args;
    return $args;
}
    
1;
