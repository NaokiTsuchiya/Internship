#!/usr/bin/env perl
use Mojolicious::Lite;
use WebService::Solr;
use WebService::Solr::Query;
use WebService::Solr::Response;

my $query = '';

get '/' => sub {
    my $c = shift;
    my $id = 'index';
	$c->render('index', query => $query, id => $id);
};

get '/search' => sub {
    my $c = shift;
    my @fq;
    my $fq = $c->req->params->every_param('fq');
    my $query = $c->param('q');
    my $unique_key = 'url';
    my $start = $c->param('start') ? $c->param('start') : 0; 
    my $row = 10;
    my $hl_simple_pre = '<span>';
    my $hl_simple_post = '</span>';
    my %params = (
        "start" => $start,
        "fq" => $fq,
        "hl.simple.pre" => $hl_simple_pre,
        "hl.simple.post" => $hl_simple_post
    );
    my $solr = WebService::Solr->new('http://localhost:8983/solr/livedoor');
    my $result;
    my @query = split(/(\s)/, $query);
    eval {
		$result = $solr->search(WebService::Solr::Query->new({-default => [@query]}), \%params);
	};
	if($@) {
		$c->render('index');
	}
    
    my $id = 'result';
    $c->render('search', query => $query, result => $result, unique_key => $unique_key, fq => $fq, start => $start, row => $row, id => $id);
};

app->start;

__DATA__
@@ index.html.ep
% layout 'common';
    <div class="container">
        <h1>Solr Client</h1>
        <div id="search" class="">
            <form class="form" action="/search" method="get">
                <p class="form-group">
                    <input class="form-control input-lg" type="text" name="q" value="<%= $query %>" placeholder="キーワードを入力">
                    <button class="btn btn-primary btn-lg" type="submit"><span class="glyphicon glyphicon-search" aria-hidden="true"></span></button>
                </p>
            </form>
        </div>
    </div>

@@ search.html.ep
<%
    layout 'common';
    my $numFound = $result->pager->total_entries;
    my $start_num = $start + 1 < $numFound ? $start + 1 : $numFound;
    my $end_num = $start + $row < $numFound ? $start + $row : $numFound;
    my $hl_snipets = 2;
    my @filed = ('title', 'date', 'body');
    my @facet_filed = ('cat', 'date');
    my %facet_to = (cat => 'カテゴリー', date => '日付');
    my $num_fq = 1;
    my $QTime = $result->content->{responseHeader}->{QTime};
%>
    <header>
        <div>
            <h1>Solr Client</h1>
            <div id="search">
                <form class="form" action="/search" method="get">
                    <p class="form-group">
                        <input class="form-control" type="text" name="q" value="<%= $query %>" placeholder="キーワードを入力">
                        <button class="btn btn-primary" type="submit"><span class="glyphicon glyphicon-search" aria-hidden="true"></span></button>
                    </p>
                </form>
            </div>
        </div>
    </header>
    <div class="container">
        <div>
            <p>検索結果：<%= $numFound %>件中<%= $start_num%> - <%= $end_num %>件(<%= $QTime / 100 %>秒)</p>
        </div>
        <div id="facet">
<%
    for my $ff (@facet_filed) {
%>
            <nav>
                <dl>
                    <dt><span class="glyphicon glyphicon-filter" aria-hidden="true"></span><%= $facet_to{$ff} %></dt>
<%
        my $facet;
        if ($ff ne 'date') {
            $facet = $result->facet_counts()->{facet_fields}->{$ff};
        }
        else {
            $facet = $result->facet_counts()->{facet_ranges}->{$ff}->{counts};
        }
        my $i = 0;
        foreach (@$facet) {
            my $k = $facet->[$i]; $i++;
            my $v = $facet->[$i]; $i++;
            next if (! $v);
            my $addfq;
            if ($ff ne 'date') {
                $addfq = $ff . ':' . $k;
            } else {
                $addfq = 'date:[' . $k . ' TO ' . $k . '+1YEAR]';
                if ($k =~ /^([0-9]{4})/ ) {
                    $k = $1 . '年';
                }
            }
            my $url = url_with;
            if (@$fq < $num_fq) {
                $url = $url->query([fq => $addfq, start => 0]);
            }
            elsif (@$fq == $num_fq) {
                
                $url = $url->query([fq => [@$fq , $addfq], start => 0]);
            }
%>
                    <dd><a href="<%= $url %>"><%= $k %></a>(<%= $v %>)</dd>
%       }
                </dl>
            </nav>
%   }
        </div>
        <div id="main" class=""clearfix>
<%
    my $key;
    for my $doc ($result->docs) {
%>
            <div class="content">
                <section>
<%
    for my $field ($doc->field_names) {
        if ($field eq $unique_key) {
            $key = $doc->value_for($field);
            last;
        }
    }
    for my $field (@filed) {
        my $highlight_text = '';
        if ($field eq 'title' || $field eq 'body') {
            my $highlighting_ref = $result->content()->{'highlighting'}->{$key}->{$field};
            my @highlighting = ();
            for my $i (0 .. $hl_snipets) {
                my $h = $highlighting_ref->[$i];
                next if ( ! $h );
                push (@highlighting, $h);
            }
            $highlight_text = join(' ... ', @highlighting);
        }
        if ($highlight_text ne '') {
            if ($field eq 'title') {
%>
                <h2><a href="<%= $key %>"><%= b ($highlight_text) %></a></h2>
%           } else { 
                        <p><%= b ($highlight_text) %></p>
<%
            }
        } elsif ($doc->values_for($field) > 1) {
%>
                    <p><%= join(',', $doc->values_for($field)) %></p>
<%      
        } else {
            if ($doc->value_for($field) =~ /^([0-9]{4}-[0-9]{2}-[0-9]{2})T(.*)Z$/) {
                my $date = $1;
                $date =~ s/-/\//g;
%>
                        <span class="date"><%= $date %></span>
%           } else {
                        <p><%= $doc->value_for($field) %></p>
<%
            }
        }
    }
%>
                </section>
            </div>
%   }
            <div id="pagenation"><!-- START Pagenation -->
                <nav>
                    <ul>
<%
    my $wsiz = 10;
    my $w1 = 5;
    my $w2 = 5;
    my $pcnt = int($numFound / $row + (($numFound % $row) == 0 ? 0 : 1));
    my $cpag = int($start / $row + 1);
    my $wbgn = $cpag - $w1;
    my $wend = $cpag + $w2;
    
    if ($wbgn < 1) {
        $wbgn = 1;
        $wend = $wbgn + $wsiz;
        if ($wend > $pcnt + 1) {
            $wend = $pcnt + 1;
        }
    }
    if ($wend > $pcnt + 1) {
        $wend = $pcnt + 1;
        $wbgn = $wend - $wsiz;
        if ($wbgn < 1) {
            $wbgn = 1;
        }
    }
    
    if ($cpag > 1) {
%>
              <li><a href="<%= url_with->query([start => ($cpag - 2) * $row]) %>"><span class="glyphicon glyphicon-chevron-left" aria-hidden="true"></span>前へ</a></li>
<%
    }
    
    for (my $i = $wbgn; $i < $wend; $i++) {
        if ($cpag == $i) {
%>
                        <li class="current"><%= $i %></li>
<%
        } else {
%>
                        <li><a href="<%= url_with->query([start => ($i - 1) * $row]) %>"><%= $i %></a></li>
<%
        }
    }

    if ($cpag < $pcnt) {
%>
                        <li><a href="<%= url_with->query([start => $cpag * $row]) %>">次へ<span class="glyphicon glyphicon-chevron-right" aria-hidden="true"></span></a></li>
<%
    }
%>
                    </ul>
                </nav>
            </div><!-- END Pagenation -->
        </div>
    </div>