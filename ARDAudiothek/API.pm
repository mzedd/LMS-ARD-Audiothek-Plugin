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

sub getHomescreen {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'homescreen';

    my $adapter = sub {
        my $content = shift;

        my $discoverEpisodelist = _episodelistFromJson($content->{_embedded}->{"mt:stageItems"}->{_embedded}->{"mt:items"});
        my $mostPlayedEpisodelist = _episodelistFromJson($content->{_embedded}->{"mt:mostPlayed"}->{_embedded}->{"mt:items"});

        my $homescreen = {
            discoverEpisodelist => $discoverEpisodelist,
            mostPlayedEpisodelist => $mostPlayedEpisodelist
        };

        $callback->($homescreen);
    };

    _call($url, $adapter);
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

    _call($url, $callback);
}

sub getProgramSet {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "programsets/$args->{programSetID}?order=desc&offset=$offset&limit=$args->{limit}";

    _call($url, $callback);
}

sub getCollectionContent {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "editorialcollections/$args->{collectionID}?offset=$offset&limit=$args->{limit}";

    _call($url, $callback);
}

sub getOrganizations {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'organizations';

    _call($url, $callback);

}

sub getItem {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'items/' . $args->{id};

    _call($url, $callback);
}

sub clearCache {
    $cache->cleanup();
}

sub getItemFromCache {
    my $id = shift;

    my $url = API_URL . 'items/' . $id;
    my $cacheKey = md5_hex($url);

    if($cacheKey && (my $cached = $cache->get($cacheKey))) {
        $log->info("Using cached data for url: $url");
        return $cached;
    }

    return undef;
}

sub _episodelistFromJson {
    my $jsonEpisodeList = shift;
    my @episodeList;

    for my $jsonEpisode (@{$jsonEpisodeList}) {

        push (@episodeList, _episodeFromJson($jsonEpisode)); 
    }

    return \@episodeList;
}

sub _episodeFromJson {
    my $jsonEpisode = shift;
    
    my $episode = {
        url => $jsonEpisode->{_links}->{"mt:bestQualityPlaybackUrl"}->{href}, 
        image => $jsonEpisode->{_links}->{"mt:image"}->{href},
        duration => $jsonEpisode->{duration},
        id => $jsonEpisode->{id},
        description => $jsonEpisode->{synopsis},
        title => $jsonEpisode->{title},
        show => $jsonEpisode->{_embedded}->{"mt:programSet"}->{title}
    };

    return $episode;
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
            $log->error("An error occured calling $url.");
        },
        { timeout => TIMEOUT_IN_S }
    )->get($url);
}

1;
