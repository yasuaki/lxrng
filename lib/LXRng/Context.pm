package LXRng::Context;

use strict;
use LXRng;

sub new {
    my ($self, %args) = @_;

    $self = bless({}, $self);

    if ($args{'query'}) {
	# CGI::Simple appears to confuse '' with undef for SCRIPT_NAME.
	# $$self{'req_url'} = $args{'query'}->url();
	$$self{'req_url'} =
	    $args{'query'}->url(-base => 1).'/'.$ENV{'SCRIPT_NAME'};

	foreach my $p ($args{'query'}->param) {
	    $$self{'params'}{$p} = [$args{'query'}->param($p)];
	}
	my @prefs = $args{'query'}->cookie('lxr_prefs');
	if (@prefs) {
	    $$self{'prefs'} = { 
		map { /^(.*?)(?:=(.*)|)$/; ($1 => $2) } @prefs };
	}
	@$self{'tree', 'path'} = $args{'query'}->path_info =~ m,([^/]+)/*(.*),;
	$$self{'tree'} = $args{'query'}->param('tree') 
	    if $args{'query'}->param('tree');
    }
    if ($args{'tree'}) {
	$$self{'tree'} = $args{'tree'};
    }

    if ($$self{'tree'} =~ s/[+](.*)$//) {
	$$self{'release'} = $1 if $1 ne '*';
    }

    if ($$self{'tree'}) {
	my $tree = $$self{'tree'};
	my @config = $self->read_config();
	die("No config for tree $tree") 
	    unless ref($config[0]) eq 'HASH' and exists($config[0]{$tree});

	$$self{'config'} = $config[0]{$tree};
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

	return @config;
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
	$base =~ s/lxr$//;
    }

    $base =~ s,/+$,,;

    return $base if $notree;

    $base .= '/'.$self->vtree.'/';
    $base =~ s,//+$,/,;

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
