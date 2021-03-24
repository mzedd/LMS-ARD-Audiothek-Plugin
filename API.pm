package Plugins::ARDAudiothek::API;

use strict;

use JSON::XS::VersionOneAndTwo;
use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Cache;

use constant API_URL => 'https://api.ardaudiothek.de/';
use constant TIMEOUT_IN_S => 20;
use constant CACHE_TTL_IN_S => 24 * 3600;

my $log = logger('plugin.ardaudiothek');
my $cache = Slim::Utils::Cache->new();

sub getDiscoverEpisodes {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'homescreen';

    _call($url, $callback);
}

sub getEditorialCategories {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'editorialcategories';

    _call($url, $callback);
}

sub getEditorialCategoryPlaylists {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'editorialcategories/' . $args->{editorialCategoryID};

    _call($url, $callback);
}

sub search {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "search/$args->{searchType}?query=$args->{searchWord}&offset=$offset&limit=$args->{limit}";

    $log->info("$url");

    _call($url, $callback);
}

sub clearCache {
    $cache->cleanup();
}

# low level api call
# caching is inspired by 
# https://forums.slimdevices.com/showthread.php?104217-Menu-handling-problem&p=828666&viewfull=1 and
# https://github.com/philippe44/LMS-YouTube/blob/master/plugin/API.pm#L140
sub _call {
    my ($url, $callback) = @_;
    
    my $cacheKey = md5_hex($url);

    if($cacheKey && (my $cached = $cache->get($cacheKey))) {
        $log->info("Using cached data for url: $url");
        $callback->($cached);
        return;
    }

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $response = shift;

            my $content = eval { from_json($response->content) };
            
            $cache->set($cacheKey, $content, CACHE_TTL_IN_S);

            $callback->($content);
        },
        sub {
            $log->error("An error occured.");
        },
        { timeout => TIMEOUT_IN_S }
    )->get($url);
}

1;
