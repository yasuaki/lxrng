package LXRng::Markup::Dir;

use strict;
use POSIX qw(strftime);
use LXRng::Cached;

sub new {
    my ($class, %args) = @_;

    return bless(\%args, $class);
}

sub context {
    my ($self) = @_;
    return $$self{'context'};
}

sub _format_time {
    my ($secs, $zone) = @_;

    my $offset = 0;
    if ($zone and $zone =~ /^([-+])(\d\d)(\d\d)$/) {
	$offset = ($2 * 60 + $3) * 60;
	$offset = -$offset if $1 eq '-';
	$secs += $offset;
    }
    else {
	$zone = '';
    }
    return strftime("%F %T $zone", gmtime($secs));
}

sub listing {
    my ($self) = @_;

    cached {
	my @list;
	foreach my $n ($$self{'node'}->contents) {
	    if ($n->isa('LXRng::Repo::Directory')) {
		push(@list, {'name' => $n->name,
			     'node' => $n->node,
			     'size' => '',
			     'time' => '',
			     'desc' => ''});
	    }
	    else {
		my $rfile_id = $self->context->config->{'index'}->rfile_id($n);
		my ($s, $tz) = 
		    $self->context->config->{'index'}->get_rfile_timestamp($rfile_id);
		($s, $tz) = $n->time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/
		    unless $s;
		
		push(@list, {'name' => $n->name,
			     'node' => $n->node,
			     'size' => $n->size,
			     'time' => _format_time($s, $tz),
			     'desc' => ''});
	    }
	}
	\@list;
    } $$self{'node'};
}

1;
