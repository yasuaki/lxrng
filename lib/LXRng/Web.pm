# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no> and others.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::Web;

use strict;

use LXRng;
use LXRng::Context;
use LXRng::Lang;
use LXRng::Parse::Simple;
use LXRng::Markup::File;
use LXRng::Markup::Dir;
use Subst::Complex;

use Template;
use IO::Handle;
use Digest::SHA1 qw(sha1_hex);
use CGI::Ajax;
use File::Temp qw(tempdir tempfile);
use File::Path qw(mkpath);
use POSIX qw(waitpid);

# Cache must be purged if this is changed.
use constant FRAGMENT_SIZE => 1000;

use vars qw($has_gzip_io);
eval { require PerlIO::gzip; $has_gzip_io = 1; };

# Return 1 if gzip compression of html is desired.

sub do_compress_response {
    my ($query) = @_;

    my @enc = split(",", $query->http('Accept-Encoding'));
    return $has_gzip_io && grep { $_ eq 'gzip' } @enc;
}


# Progressive output of marked-up file.  If the file in question
# exists in cache, and this is the initial load of an ajax-requested
# file, return only the lines the user wants to see (with a minimum of
# context) as a first approximation.

sub print_markedup_file {
    my ($context, $template, $node) = @_;

    autoflush STDOUT 1;

    unless ($node) {
	print('<div class="error">File not found.</div>');
	return;
    }

    if ($node->isa('LXRng::Repo::Directory')) {
	my $markup = LXRng::Markup::Dir->new('context' => $context,
					     'node' => $node);
	$template->process('content_dir.tt2',
			   {'context' => $context,
			    'dir_listing' => $markup->listing})
	    or die $template->error();
	return;
    }

    my $line   = 0;
    my $focus  = 1;
    my $fline  = $context->param('line');

    $focus = $fline < FRAGMENT_SIZE if defined($fline);

    my $shaid = sha1_hex(join("\0", $node->name, $node->revision,
			      $context->release));
    my $cfile;
    $shaid =~ s,^(..)(..),$1/$2/,;
    $shaid .= '_3'; # Cache file format generation indicator
    $cfile = $context->config->{'cache'}.'/'.$shaid
	if exists $context->config->{'cache'};

    if ($cfile and -e "$cfile/.complete") {
	print("<div id=\"file_contents\">");
	while (-r "$cfile/$line") {
	    print("<pre class=\"".($focus ? "done" : "pending").
		  "\" id=\"$shaid/$line\">");
	    if ($focus) {
		open(my $cache, '<', "$cfile/$line");
		my $buf;
		while (read($cache, $buf, 16384) > 0) {
		    print($buf);
		}
		close($cache);
	    }
	    else {
		print("<a class=\"line\"></a>\n" x FRAGMENT_SIZE);
	    }
	    print("</pre>");
	    $line += FRAGMENT_SIZE;

	    if (defined($fline)) {
		$focus = ($line <= ($fline + 100)
			  and $line > ($fline - FRAGMENT_SIZE));
	    }
	}
	print("</div>\n");
	return "use:".$shaid;
    }

    my $cache;
    if ($cfile) {
	mkpath($cfile, 0, 0777);
	open($cache, '>', "$cfile/0");
    }
    my $handle = $node->handle();
    LXRng::Lang->init($context);
    my $lang   = LXRng::Lang->new($node);
    my $parse  = LXRng::Parse::Simple->new($handle, 8,
					   @{$lang->parsespec});
    my $markup = LXRng::Markup::File->new('context' => $context);
    my $subst  = $lang->markuphandlers($context, $node, $markup);

    print("<div id=\"file_contents\">".
	  "<pre class=\"".($focus ? "done" : "pending").
	  "\" id=\"$shaid/0\">");
    while (1) {
	my @frags = map { split(/(?<=\n)/, $_) }
	$markup->markupfile($subst, $parse);
	last unless @frags;
	foreach my $f (@frags) {
	    print($f) if $focus;
	    print($cache $f) if $cache;
	    if ($f =~ /\n$/s) {
		$line++;
		if ($line % FRAGMENT_SIZE == 0) {
		    print("<a class=\"line\"></a>\n" x FRAGMENT_SIZE)
			unless $focus;
		    if (defined($fline)) {
			$focus = ($line <= ($fline + 100)
				  and $line > ($fline - FRAGMENT_SIZE));
		    }
		    print("</pre>".
			  "<pre class=\"".
			  ($focus ? "done" : "pending").
			  "\" id=\"$shaid/$line\">");
		    if ($cache) {
			close($cache);
			open($cache, '>', "$cfile/$line");
		    }
		}
	    }
	}
    }
    print("</pre></div>\n");
    if ($cache) {
	close($cache);
	open($cache, '>', "$cfile/.complete");
	close($cache);
    }

    return "gen:".$shaid;
}

sub print_error {
    my ($context, $template, $query, $error) = @_;

    my $tmpl;
    if ($context->config and $context->config->{'repository'}) {
	$tmpl = 'error.tt2';
    }
    else {
	$tmpl = 'bare_error.tt2';
    }

    print($query->header(-type => 'text/html',
			 -charset => 'utf-8'));

    my $base = $context->base_url();
    $template->process($tmpl,
		       {'context' => $context,
			'base_url' => $base,
			'error' => $error})
	or die $template->error();
}    

sub print_tree_list {
    my ($context, $template) = @_;

    my $base = $context->base_url(1);
    $base =~ s,[+]trees/?$,,;
    $template->process('tree_list.tt2',
		       {'context' => $context,
			'base_url' => $base})
	or die $template->error();
}    

sub print_release_list {
    my ($context, $template) = @_;

    $template->process('release_select.tt2',
		       {'context' => $context})
	or die $template->error();
}

sub source {
    my ($context, $template, $query, $template_extra_args) = @_;

    my $pjx = CGI::Ajax->new('pjx_search' => '',
			     'pjx_load_file' => '',
			     'pjx_load_fragment' => '',
			     'pjx_releases' => '');
    $pjx->js_encode_function('escape');

    if ($context->prefs and $context->prefs->{'navmethod'} eq 'ajax') {
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8'));
	if ($context->tree ne '') {
	    my $base = $context->base_url(1);
	    my $path = $context->vtree.'/'.$context->path;
	    # print($query->redirect($base.'#'.$path));

	    $template->process('ajax_redir.tt2',
			       {'ajax_url' => $base.'#'.$path})
		or die $template->error();
	}
	else {
	    if ($context->release eq 'trees') {
		print_tree_list($context, $template);
	    }
	    else {
		my $base = $context->base_url(1);
		$base =~ s,/*$,/ajax+*/,;

		# This is a bit fragile, but only covers a relatively
		# esoteric corner case.  (CGI::Ajax splits results on
		# __pjx__, and there doesn't seem to be any provisions
		# for escaping any randomly occurring split markers.)
		my $js = $pjx->show_javascript();
		$js =~ s/var splitval.*var data[^;]+/var data = rsp/;

		$template->process('main.tt2',
				   {'context'    => $context,
				    'base_url'   => $base,
				    'javascript' => $js,
				    'is_ajax' => 1})
		    or die $template->error();
	    }
	}
	return;
    }

    if ($context->tree eq '') {
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8'));
	print_tree_list($context, $template);
	return;
    }


    my $ver = $context->release;
    my $rep = $context->config->{'repository'};
    unless ($rep) {
	print_error($context, $template, $query,
		    "No/unknown tree indicated");
	return;
    }

    my $node = $rep->node($context->path, $ver);
    unless ($node) {
	print_error($context, $template, $query,
		    "Node not found: ".$context->path." ($ver)");
	return;
    }

    my $gzip = do_compress_response($query);

    my @history = $query->cookie('lxr_history_'.$context->tree);
    if ($node->isa('LXRng::Repo::File')) {
	my $h = $context->path.'+'.$ver;
	@history = ($h, grep { $_ ne $h } @history);
	splice(@history, 15) if @history > 15;
    }

    my $lxr_hist = $query->cookie(-name    => 'lxr_history_'.$context->tree,
				  -values  => \@history,
				  -expires => '+1y');

    print($query->header(-type => 'text/html',
			 -charset => 'utf-8',
			 -cookie => $lxr_hist,
			 $gzip ? (-content_encoding => 'gzip') : ()));

    binmode(\*STDOUT, ":gzip") if $gzip;

    my @rels = @{$context->all_releases()};
    unshift(@rels, $rels[0]);
    while (@rels > 2 and $rels[1] ne $context->release) {
	shift(@rels);
    }

    my $ver_next = @rels > 1 ? $rels[0] : $context->release;
    my $ver_prev = @rels > 2 ? $rels[2] : $context->release;

    my %template_args = (%{$template_extra_args || {}},
			 'context'    => $context,
			 'tree'	      => $context->tree,
			 'node'       => $node,
			 'ver_prev'   => $ver_prev,
			 'ver_next'   => $ver_next,
			 'base_url'   => $context->base_url,
			 'javascript' => $pjx->show_javascript());


    if ($context->prefs and $context->prefs->{'navmethod'} eq 'popup') {
	$template_args{'is_popup'} = 1;
	$template_args{'popup_serial'} = int(rand(1000000));
    }

    if ($node->isa('LXRng::Repo::Directory')) {
	my $markup = LXRng::Markup::Dir->new('context' => $context,
					     'node' => $node);
	$template->process('main.tt2',
			   {%template_args,
			    'dir_listing' => $markup->listing,
			    'is_dir' => 1})
	    or die $template->error();
	return;
    }
    else {
	my $html = '';
	$template->process('main.tt2',
			   {%template_args,
			    'file_content' => '<!--FILE_CONTENT-->',
			    'is_dir' => 0},
			   \$html)
	    or die $template->error();
	
	# Template directives in processed template.  Sigh.  TT2 sadly
	# can't do progressive rendering of its templates, so we cheat...
	my ($pre, $post) = split('<!--FILE_CONTENT-->', $html);
	print($pre);
	my $id = print_markedup_file($context, $template, $node);
	print($post);

	return $id;
    }

    # TODO: This is potentially useful, in that it resets the stream
    # to uncompressed mode.  However, under Perl 5.8.8+PerlIO::gzip
    # 0.18, this seems to truncate the stream.  Not strictly needed
    # for CGI, reexamine when adapting to mod_perl.
    ## binmode(\*STDOUT, ":pop") if $gzip;
}


# Perform various search operations.  Return results as html suitable
# both as a response to an ajax request and inclusion in a more
# general html document.

sub search {
    my ($context, $template, $type, $find) = @_;

    my $ver = $context->release;
    $find ||= $context->param('search');

    my $index = $context->config->{'index'};
    my $rel_id = $index->release_id($context->tree, $ver);
    my %template_args = ('context' => $context);

    $template_args{'navtarget'} = 'target='.$context->param('navtarget')
	if $context->param('navtarget');


    if ($find =~ /\S/) {
	if ($find =~ /^(ident|code):(.*)/) {
	    $type = 'code';
	    $find = $2;
	}
	elsif ($find =~ /^(file|path):(.*)/) {
	    $type = 'file';
	    $find = $2;
	}
	elsif ($find =~ /^(text):(.*)/) {
	    $type = 'text';
	    $find = $2;
	}

	if ($type eq 'file' or $type eq 'search') {
	    my $files = $index->files_by_wildcard($context->tree,
						  $ver, $find);
	    $template_args{'file_res'} = {'query' => $find,
	    				  'files' => $files,}
	}
	if ($type eq 'text' or $type eq 'search') {
	    my $hash  = $context->config->{'search'};
	    my ($total, $res) = $hash->search($rel_id, $find);

	    $template_args{'text_res'} = {'query' => $find,
					  'total' => $total,
					  'files' => $res};
	}
	if ($type eq 'code' or $type eq 'search') {
	    my $result = $index->identifiers_by_name($context->tree, 
						     $ver, $find);
	    my @cooked = (map { $$_[1] = ucfirst($LXRng::Lang::deftypes{$$_[1]});
				$_ }
			  sort { $LXRng::Lang::defweight{$$b[1]} cmp
				     $LXRng::Lang::defweight{$$a[1]} ||
				     $$a[2] cmp $$b[2] ||
				     $$a[3] <=> $$b[3] }
			  @$result);
	    $template_args{'code_res'} = {'query' => $find,
					  'idents' => \@cooked};
	}
	if ($type eq 'ident') {
	    my $usage  = $context->config->{'usage'};
	    my ($symname, $symid, $ident, $refs) =
		$index->get_identifier_info($usage, $find, $rel_id);

	    $$ident[1] = ucfirst($LXRng::Lang::deftypes{$$ident[1]});
	    $$ident[5] &&= $LXRng::Lang::deftypes{$$ident[5]};

	    $template_args{'ident_res'} = {'query' => $symname,
					   'ident' => $ident,
					   'refs' => $refs};
	}
	if ($type eq 'ambig') {
	    my $rep = $context->config->{'repository'};
	    my @args = grep {
		$rep->node($_, $context->release)
		} split(/\|/, $find);
	    $template_args{'ambig_res'} = {'query' => $find,
					   'files' => \@args,}
	}
    }
    else {
	$template_args{'error'} = 'No query string given';
    }
    my $html = '';
    $template_args{'tree'} = $context->tree;
    $template_args{'search_type'} = $type if
	$type =~ /^(search|file|text|code|ident|ambig)$/;
    $template->process('search_result.tt2',
		       \%template_args,
		       \$html)
	or die $template->error();
    return $html;
}


# Display search results for plain and popup navigation methods.
# (Ajax methods call "search" directly.)

sub search_result {
    my ($context, $template, $query, $result) = @_;

    my %template_args = ('context'    => $context,
			 'tree'	      => $context->tree,
			 'search_res' => $result,
			 'base_url'   => $context->base_url);

    if ($context->prefs and $context->prefs->{'navmethod'} eq 'popup') {
	my $gzip = do_compress_response($query);

	print($query->header(-type => 'text/html',
			     -charset => 'utf-8',
			     $gzip ? (-content_encoding => 'gzip') : ()));

	binmode(\*STDOUT, ":gzip") if $gzip;

	$template->process('popup_main.tt2',
			   {%template_args,
			    'is_popup' => 1})
	    or die $template->error();
    }
    else {
	$context->path('');
	source($context, $template, $query, \%template_args);
    }
}


# Callback to perform the ajax-available functions.

sub handle_ajax_request {
    my ($query, $context, $template) = @_;
    my $gzip = do_compress_response($query);
    
    # $query->no_cache(1); FIXME -- not available with CGI.pm.
    my %headers = (-type => 'text/html',
		   -charset => 'utf-8');
    $headers{'-cache-control'} = 'no-store, no-cache, must-revalidate'
	unless $context->param('fname') eq 'pjx_load_fragment';
    $headers{'-content_encoding'} = 'gzip' if $gzip;

    print($query->header(%headers));
    binmode(\*STDOUT, ":gzip") if $gzip;

    if ($context->param('fname') eq 'pjx_load_file') {
	unless ($context->config and $context->config->{'repository'}) {
	    print('<div class="error">No/unknown tree indicated.</div>');
	    return;
	}
	my $rep = $context->config->{'repository'};
	my $node = $rep->node($context->param('file'), $context->release);
	print_markedup_file($context, $template, $node);
	
    }
    elsif ($context->param('fname') eq 'pjx_load_fragment') {
	my $shaid = $context->param('frag');
	return unless $shaid =~ 
	    m|^[0-9a-z]{2}/[0-9a-z]{2}/[0-9a-z]{36}_\d+/[0-9]+$|;
	return unless exists $context->config->{'cache'};
	my $cfile = $context->config->{'cache'}.'/'.$shaid;
	return unless -e $cfile;
	open(my $cache, '<', $cfile) or return;
	
	print($shaid.'|');
	my $buf;
	while (read($cache, $buf, 16384) > 0) {
	    print($buf);
	}
	close($cache);
    }
    elsif ($context->param('fname') eq 'pjx_search') {
	if ($context->param('ajax_lookup') =~
	    /^[+ ](code|ident|file|text|ambig)=(.*)/)
	{
	    print(search($context, $template, $1, $2));
	}
	else {
	    print(search($context, $template, 'search',
			 $context->param('search')));
	}
    }
    elsif ($context->param('fname') eq 'pjx_releases') {
	print_release_list($context, $template);
    }

    # binmode(\*STDOUT, ":pop") if $gzip;    
}


# Stuff user preferences in cookie.

sub handle_preferences {
    my ($query, $context, $template) = @_;

    if ($context->param('resultloc')) {
	my @prefs;
	if ($context->param('resultloc') =~ /^(replace|popup|ajax)$/) {
	    push(@prefs, 'navmethod='.$1);
	}
	my $lxr_prefs = $query->cookie(-name    => 'lxr_prefs',
				       -values  => \@prefs,
				       -expires => '+1y');
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8',
			     -cookie => $lxr_prefs));

	my %template_args;
	if (defined($context->param('return'))) {
	    $template_args{'return'} = $query->param('return');
	}
	else {
	    $template_args{'return'} = $context->base_url(1);
	}
	
	$template->process('prefs_set.tt2',
			   \%template_args)
	    or die $template->error();
    }
    else {
	print($query->header(-type => 'text/html',
			     -charset => 'utf-8'));

	my $nav = 'is_replace';
	$nav = 'is_'.$context->prefs->{'navmethod'} if
	    $context->prefs and $context->prefs->{'navmethod'} ne '';
	
	my $ret = $context->base_url();
	$ret =~ s,[+]prefs/?,,;
	$ret .= $query->param('return') if $query->param('return');

	$template->process('prefs.tt2',
			   {'return' => $ret,
			    $nav => 1})
	    or die $template->error();
    }
}


# Generate pdf listing of given file.  Much if the following lifted
# from the script "texify".  Proof of concept, code quality could be
# better.

sub generate_pdf {
    my ($query, $context, $template, $path) = @_;

    my $tempdir = tempdir(CLEANUP => 1);

    my %tspecials = (
		     '$'	=> '\$',	'*'	=> "\$\\ast\$",
		     '&'	=> '\&',	'%'	=> '\%',
		     '#'	=> '\#',	'_'	=> '\_',
		     '^'	=> '\^{}',	'{'	=> '\{',
		     '}'	=> '\}',	'|'	=> "\$|\$",
		     '['	=> '{[}',	']'	=> '{]}',
		     "'"	=> "{'}",	"\""	=> "\\string\"",
		     '~'	=> '\~{}',	'<'	=> "\$<\$",
		     '>'	=> "\$>\$",	"\\"	=> "\$\\backslash\$",
		     '-'	=> '\dash{}',
# These are latin1-replacements, and interact badly with utf8...
		     "\242"	=> '?',		"\244"	=> '?',
		     "\245"	=> '?',		"\246"	=> '?',
		     "\252"	=> "\$\252\$",	"\254"	=> "\$\254\$",
		     "\255"	=> "\\dash{}",	"\260"	=> "\$\260\$",
		     "\261"	=> "\$\261\$",	"\262"	=> "\$\262\$",
		     "\263"	=> "\$\263\$",	"\265"	=> "\$\265\$",
		     "\271"	=> "\$\271\$",	"\272"	=> "\$\272\$",
		     "\327"	=> "\$\327\$",	"\367"	=> "\$\367\$",
		     );

    my $tspecials = join('', map { quotemeta($_) } keys(%tspecials));

    my $ver = $context->release;
    my $rep = $context->config->{'repository'};
    my $node = $rep->node($path, $ver);

    die "No such file" unless $node;

    my $handle = $node->handle();
    LXRng::Lang->init($context);
    my $lang   = LXRng::Lang->new($node);
    my $parse  = LXRng::Parse::Simple->new($handle, 8,
					   @{$lang->parsespec});
    my $res    = $lang->reserved();
    my $resre;
    if (%$res) {
	$resre = '(?:(?<=[\s\W])|^)('.
	    join('|', map { "\Q$_\E" }
		 sort { length($b) <=> length($a) }
		 keys %$res).')(?=$|[\s\W])';
    }

    my @lines;
    my $row = 1;
    my $col = 0;
    my $line = '\\lxrln{1}';
    my %ptabs = ();
    my %ntabs = ();

    while (1) {
	my ($btype, $frag) = $parse->nextfrag;
	
	last unless defined $frag;

	$btype ||= 'code';
	my @parts = split(/(\n)/, $frag);

	while (@parts) {
	    my $part  = shift(@parts);
	    my $align = 0;
	    my $cont  = 0;

	    if ($part eq "\n") {
		push(@lines, $line);
		%ptabs = %ntabs;
		%ntabs = ();

		$col = 0;
		$row++;
		if ($row % 5 == 0) {
		    $line = "\\lxrln{$row}";
		}
		else {
		    $line = '';
		}
		next;
	    }

	    if ($part =~ /^(.*?)( +)(.*)/) {
		unshift(@parts, $3);
		$part  = $1;
		if (length($2) > 2 or $ptabs{$col + length($1) + length($2)}) {
		    $align = 1;
		    $col += length($2);
		    $ntabs{$col + length($part)} = 1;
		}
		else {
		    $part .= $2;
		}
	    }
	    $col += length($part);

	    if ($btype eq 'code') {
		$part =~ s/$resre/\\bf{}\\sffamily{}$1\\sf{}/g if $resre;
	    }
	    elsif ($btype eq 'include') {
		# This is a bit of a special treatment for C...
		$part =~ s((<[^>]*>|\"[^\"]*\")|$resre)
		    ($1 ? "$1" : "\\bf{}\\sffamily{}$2\\sf{}")ge if $resre;
	    }
	    elsif ($btype eq 'comment') {
		$part = '\\em{}'.$part.'\\sf{}';
	    }
	    elsif ($btype eq 'string') {
		$part = '\\tt{}'.$part.'\\sf{}';
	    }

	    $part =~ s{(\\(?:sf|bf|em|tt|sffamily)\{\})|
			   ([*=])|
			   ([ ]+)|
			   ([$tspecials\0-\010\013\014\016-\037\200-\240])|
			   ([[:alnum:]]+|.)}
	    {
		if (defined $1) {
		    $1;
		}
		elsif (defined $2) {
		    "\\lxgr{".(exists $tspecials{$2} ? $tspecials{$2} : $2)."}";
		}
		elsif (defined $3) {
		    "\\lxws{$3}";
		}
		elsif (defined $4) {
		    "\\lxlt{".(exists $tspecials{$4} ? $tspecials{$4} : '?')."}";
		}
		else {
		    "\\lxlt{$5}";
		}
	    }gex;

	    $line .= $part;
	    if ($align) {
		$line .= "\\lxalign{$col}";
	    }
	}
    }

    if ($line ne '') {
	push(@lines, $line);
    }
    else {
	$row--;
    }

    if (@lines and $row % 5 != 0) {
	$lines[$#lines] =~ s/^/\\lxrln{$row}/;
    }

    my $pathdesc = $context->tree."/$path ($ver)";
    $pathdesc =~ s/([$tspecials])/$tspecials{$1}/ge;
    
    my ($texh, $texname) = tempfile(DIR => $tempdir, SUFFIX => '.tex');

    $template->process('print_pdf.tt2',
		       {'pathdesc' => $pathdesc,
			'lines' => \@lines},
		       $texh)
	or die $template->error();

    my $pdflatex;
    my $pid = open($pdflatex, "-|");
    die $! unless defined $pid;

    if ($pid == 0) {
	close(STDERR);
	open(STDERR, ">&STDOUT");
	chdir($tempdir);
	exec("pdflatex", "$texname");
	kill(9, $$);
    }
    my @err = <$pdflatex>;
    close($pdflatex);
    my $pdfname = $texname;
    $pdfname =~ s/[.]tex$/.pdf/;
    if (-e $pdfname) {
	open(my $pdfh, "< $pdfname") or die $!;

	print($query->header(-type => 'application/pdf',
			     -content_disposition =>
			     "inline; filename=$path.pdf"));
	my $buf = '';
	while (sysread($pdfh, $buf, 65536) > 0) {
	    print($buf);
	}
	close($pdfh);
    }
    elsif (-e "$texname.output") {
	@err = splice(@err, -15) if @err > 15;
	die "PDF generation failed: ".join("\n", @err);
    }
    else {
	die "PDF generation failed";
    }
}


sub handle {
    my ($self, $query) = @_;

    my $template = Template->new({'INCLUDE_PATH' => $LXRng::ROOT.'/tmpl/'});
    my $context  = LXRng::Context->new('query' => $query);

    unless ($context->config) {
	print_error($context, $template, $query,
		    "No/unknown tree indicated");
	return;
    }

    if ($context->param('fname')) {
	handle_ajax_request($query, $context, $template);
    }
    else {	
	if ($context->path =~ /^[+ ]prefs$/) {
	    handle_preferences($query, $context, $template);
	}
	elsif ($context->path =~ /^[+ ]print=(.*)/) {
	    generate_pdf($query, $context, $template, $1);
	}
	else {
	    if ($context->path =~ 
		/^[+ ](search|code|ident|file|text|ambig)(?:=(.*)|)/)
	    {
		my $qstring = $2 || $context->param('search');
		search_result($context, $template, $query,
			      search($context, $template, $1, $2));
		$context->path('');
		return qq{[$qstring]};
	    }
	    else {
		source($context, $template, $query);
	    }
	}
    }
}

1;
