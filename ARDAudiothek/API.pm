package Plugins::ARDAudiothek::API;

use strict;

use JSON::XS::VersionOneAndTwo;
use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;

use constant API_URL => 'https://api.ardaudiothek.de/';
use constant TIMEOUT_IN_S => 20;
use constant CACHE_TTL_IN_S => 24 * 3600;

my $log = logger('plugin.ardaudiothek');
my $cache = Slim::Utils::Cache->new();
my $serverPrefs = preferences('server');

sub getHomescreen {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'homescreen';

    my $adapter = sub {
        my $content = shift;

        my $discoverEpisodes = _itemlistFromJson(
            $content->{_embedded}->{"mt:stageItems"}->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );
        
        my $editorialCollections = _itemlistFromJson(
            $content->{_embedded}->{"mt:editorialCollections"}->{_embedded}->{"mt:editorialCollections"},
            \&_playlistFromJson
        );

        my $featuredPlaylists = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredPlaylists"}->{_embedded}->{"mt:editorialCollections"},
            \&_playlistFromJson);

        my $mostPlayedEpisodes = _itemlistFromJson(
            $content->{_embedded}->{"mt:mostPlayed"}->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredProgramSets"}->{_embedded}->{"mt:programSets"},
            \&_playlistFromJson
        );

        my $homescreen = {
            discoverEpisodes => $discoverEpisodes,
            editorialCollections => $editorialCollections,
            featuredPlaylists => $featuredPlaylists,
            mostPlayedEpisodes => $mostPlayedEpisodes,
            featuredProgramSets => $featuredProgramSets
        };

        $callback->($homescreen);
    };

    _call($url, $adapter);
}

sub getEditorialCategories {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . 'editorialcategories';

    my $adapter = sub {
        my $content = shift;

        my $categorylist = _itemlistFromJson($content->{_embedded}->{"mt:editorialCategories"}, \&_categoryFromJson);
        
        $callback->($categorylist);
    };

    _call($url, $adapter);
}

sub getEditorialCategoryPlaylists {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . 'editorialcategories/' . $args->{editorialCategoryID};

    my $adapter = sub {
        my $content = shift;

        my $mostPlayedEpisodes = _itemlistFromJson(
            $content->{_embedded}->{"mt:mostPlayed"},
            \&_episodeFromJson
        );

        my $newestEpisodes = _itemlistFromJson(
            $content->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredProgramSets"},
            \&_playlistFromJson
        );

        my $programSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:programSets"},
            \&_playlistFromJson
        );

        my $editorialCategoryPlaylists = {
            mostPlayedEpisodes => $mostPlayedEpisodes,
            newestEpisodes => $newestEpisodes,
            featuredProgramSets => $featuredProgramSets,
            programSets => $programSets
        };

        $callback->($editorialCategoryPlaylists);
    };

    _call($url, $adapter);
}

sub search {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "search/$args->{searchType}?query=$args->{searchWord}&offset=$offset&limit=$args->{limit}";

    my $programSetsAdapter = sub {
        my $content = shift;
        
        my $programSetsSearchresult = {
            programSets => _itemlistFromJson($content->{_embedded}->{"mt:programSets"}, \&_playlistFromJson),
            numberOfElements => $content->{numberOfElements}
        };
            
        $callback->($programSetsSearchresult);
    };

    my $episodesAdapter = sub {
        my $content = shift;
        my $episodesSearchresult = {
            episodes => _itemlistFromJson($content->{_embedded}->{"mt:items"}, \&_episodeFromJson),
            numberOfElements => $content->{numberOfElements}
        };

        $callback->($episodesSearchresult);
    };

    my $adapter;
    if($args->{searchType} eq 'programsets') {
        $adapter = $programSetsAdapter;
    }
    elsif($args->{searchType} eq 'items') {
        $adapter = $episodesAdapter;
    }
    else {
        $callback->(undef);
    }

    _call($url, $adapter);
}

sub getPlaylist {
    my ($class, $callback, $args) = @_;

    my $url = API_URL;
    if($args->{type} eq 'programSet') {
        $url = $url . "programsets/$args->{id}?order=desc&";
    }
    elsif($args->{type} eq 'collection') {
        $url = $url . "editorialcollections/$args->{id}?";
    }
    else {
        $callback->(undef);
    }

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    $url = $url . "offset=$offset&limit=$args->{limit}";

    my $adapter = sub {
        my $jsonPlaylist = shift;

        my $playlist = {
            title => $jsonPlaylist->{title},
            id => $jsonPlaylist->{id},
            numberOfElements => $jsonPlaylist->{numberOfElements},
            description => $jsonPlaylist->{synopsis},
            episodes => _itemlistFromJson($jsonPlaylist->{_embedded}->{"mt:items"}, \&_episodeFromJson)
        };

        $callback->($playlist);
    };

    _call($url, $adapter);
}

sub getOrganizations {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . 'organizations';

    my $adapter = sub {
        my $content = shift;

        my $organizationlist = _itemlistFromJson(
            $content->{_embedded}->{"mt:organizations"},
            \&_organizationFromJson
        );

        $callback->($organizationlist);
    };

    _call($url, $adapter);
}

sub getEpisode {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'items/' . $args->{id};

    my $adapter = sub {
        my $jsonEpisode = shift;
        
        $callback->(_episodeFromJson($jsonEpisode));
    };

    _call($url, $adapter);
}

sub clearCache {
    $cache->cleanup();
}

sub getEpisodeFromCache {
    my $id = shift;

    my $url = API_URL . 'items/' . $id;
    my $cacheKey = md5_hex($url);

    if($cacheKey && (my $cached = $cache->get($cacheKey))) {
        $log->info("Using cached data for url: $url");
        return _episodeFromJson($cached);
    }

    return undef;
}

sub _itemlistFromJson {
    my $jsonItemlist = shift;
    my $itemFromJson = shift;
    my @itemlist;

    if(ref $jsonItemlist eq ref {}) {
        push (@itemlist, $itemFromJson->($jsonItemlist));
    }
    else {
        for my $jsonItem (@{$jsonItemlist}) {
            push (@itemlist, $itemFromJson->($jsonItem));
        }
    }

    return \@itemlist;
}

sub _categoryFromJson {
    my $jsonCategory = shift;

    my $category = {
        imageUrl => $jsonCategory->{_links}->{"mt:image"}->{href},
        title => $jsonCategory->{title},
        id => $jsonCategory->{id}
    };

    return $category;
}

sub _organizationFromJson {
    my $jsonOrganization = shift;

    my $organization = {
        name => $jsonOrganization->{name},
        id => $jsonOrganization->{id},
        publicationServices => _itemlistFromJson(
            $jsonOrganization->{_embedded}->{"mt:publicationServices"},
            \&_publicationServiceFromJson
        )
    };

    return $organization;
}

sub _publicationServiceFromJson {
    my $jsonPublicationService = shift;

    my $publicationService = {
        name => $jsonPublicationService->{title},
        id => $jsonPublicationService->{id},
        imageUrl => $jsonPublicationService->{_links}->{"mt:image"}->{href},
        description => $jsonPublicationService->{synopsis},
        programSets => _itemlistFromJson(
            $jsonPublicationService->{_embedded}->{"mt:programSets"},
            \&_playlistFromJson
        )
    };

    # if there is a liveStream - add it
    if($jsonPublicationService->{_embedded}->{"mt:liveStreams"}->{numberOfElements} == 1) {
        $publicationService->{liveStream} = {
            name => 'Livestream',
            imageUrl => $jsonPublicationService->{_links}->{"mt:image"}->{href},
            url => $jsonPublicationService->{_embedded}->{"mt:liveStreams"}->{_embedded}->{"mt:items"}->{stream}->{streamUrl}
        };
    }

    return $publicationService;
}

sub _playlistFromJson {
    my $jsonPlaylist = shift;

    my $playlist = {
        imageUrl => $jsonPlaylist->{_links}->{"mt:image"}->{href},
        title => $jsonPlaylist->{title},
        id => $jsonPlaylist->{id}
    };

    return $playlist;
}

sub _episodeFromJson {
    my $jsonEpisode = shift;
    
    my $episode = {
        url => $jsonEpisode->{_links}->{"mt:bestQualityPlaybackUrl"}->{href}, 
        imageUrl => $jsonEpisode->{_links}->{"mt:image"}->{href},
        duration => $jsonEpisode->{duration},
        id => $jsonEpisode->{id},
        description => $jsonEpisode->{synopsis},
        title => $jsonEpisode->{title},
        show => $jsonEpisode->{_embedded}->{"mt:programSet"}->{title}
    };

    return $episode;
}

sub selectImageFormat {
    my $imageUrl = shift;
    my $thumbnailSize = 4.0 * "$serverPrefs->{prefs}->{thumbSize}";

    $imageUrl =~ s/{ratio}/1x1/i;
    $imageUrl =~ s/{width}/$thumbnailSize/i;

    return $imageUrl;
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
