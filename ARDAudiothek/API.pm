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

        my $discoverEpisodelist = _itemlistFromJson(
            $content->{_embedded}->{"mt:stageItems"}->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );
        
        my $editorialCollections = _itemlistFromJson(
            $content->{_embedded}->{"mt:editorialCollections"}->{_embedded}->{"mt:editorialCollections"},
            \&_collectionFromJson
        );

        my $featuredPlaylists = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredPlaylists"}->{_embedded}->{"mt:editorialCollections"},
            \&_collectionFromJson);
        my $mostPlayedEpisodelist = _itemlistFromJson(
            $content->{_embedded}->{"mt:mostPlayed"}->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredProgramSets"}->{_embedded}->{"mt:programSets"},
            \&_programSetFromJson
        );

        my $homescreen = {
            discoverEpisodelist => $discoverEpisodelist,
            editorialCollections => $editorialCollections,
            featuredPlaylists => $featuredPlaylists,
            mostPlayedEpisodelist => $mostPlayedEpisodelist,
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

        my $mostPlayedEpisodelist = _itemlistFromJson(
            $content->{_embedded}->{"mt:mostPlayed"},
            \&_episodeFromJson
        );

        my $newestEpisodelist = _itemlistFromJson(
            $content->{_embedded}->{"mt:items"},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:featuredProgramSets"},
            \&_programSetFromJson
        );

        my $programSets = _itemlistFromJson(
            $content->{_embedded}->{"mt:programSets"},
            \&_programSetFromJson
        );

        my $categoryItems = {
            mostPlayedEpisodelist => $mostPlayedEpisodelist,
            newestEpisodelist => $newestEpisodelist,
            featuredProgramSets => $featuredProgramSets,
            programSets => $programSets
        };

        $callback->($categoryItems);
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

    my $programSetAdapter = sub {
        my $content = shift;
        
        my $programSetSearchresult = {
            programSetlist => _itemlistFromJson($content->{_embedded}->{"mt:programSets"}, \&_programSetFromJson),
            numberOfElements => $content->{numberOfElements}
        };
            
        $callback->($programSetSearchresult);
    };

    my $episodeAdapter = sub {
        my $content = shift;
        my $episodeSearchresult = {
            episodelist => _itemlistFromJson($content->{_embedded}->{"mt:items"}, \&_episodeFromJson),
            numberOfElements => $content->{numberOfElements}
        };

        $callback->($episodeSearchresult);
    };

    my $adapter;
    if($args->{searchType} eq 'programsets') {
        $adapter = $programSetAdapter;
    }
    elsif($args->{searchType} eq 'items') {
        $adapter = $episodeAdapter;
    }
    else {
        $callback->(undef);
    }

    _call($url, $adapter);
}

sub getProgramSet {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "programsets/$args->{programSetID}?order=desc&offset=$offset&limit=$args->{limit}";

    my $adapter = sub {
        my $jsonProgramSet = shift;

        my $programSet = {
            title => $jsonProgramSet->{title},
            id => $jsonProgramSet->{id},
            numberOfElements => $jsonProgramSet->{numberOfElements},
            description => $jsonProgramSet->{synopsis},
            episodelist => _itemlistFromJson($jsonProgramSet->{_embedded}->{"mt:items"}, \&_episodeFromJson)
        };

        $callback->($programSet);
    };

    _call($url, $adapter);
}

sub getCollectionContent {
    my ($class, $callback, $args) = @_;

    my $offset = 0;
    if(defined $args->{offset}) {
        $offset = $args->{offset};
    }

    my $url = API_URL . "editorialcollections/$args->{collectionID}?offset=$offset&limit=$args->{limit}";

    my $adapter = sub {
        my $jsonCollection = shift;

        my $collection = {
            title => $jsonCollection->{title},
            id => $jsonCollection->{id},
            numberOfElements => $jsonCollection->{numberOfElements},
            description => $jsonCollection->{synopsis},
            episodelist => _itemlistFromJson($jsonCollection->{_embedded}->{"mt:items"}, \&_episodeFromJson)
        };

        $callback->($collection);
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

sub getItem {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'items/' . $args->{id};

    my $adapter = sub {
        my $content = shift;
        
        $callback->(_episodeFromJson($content));
    };

    _call($url, $adapter);
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
        name => $jsonPublicationService->{organizationName},
        id => $jsonPublicationService->{id},
        imageUrl => $jsonPublicationService->{_links}->{"mt:image"}->{href},
        description => $jsonPublicationService->{synopsis},
        programSets => _itemlistFromJson(
            $jsonPublicationService->{_embedded}->{"mt:programSets"},
            \&_programSetFromJson
        )
    };

    # if there is a liveStream - add it
    if($jsonPublicationService->{_embedded}->{"mt:liveStreams"}->{numberOfElements} == 1) {
        $publicationService->{liveStream} = {
            name => 'Livestream',
            imageUrl => $publicationService->{_links}->{"mt:image"}->{href},
            url => $publicationService->{_embedded}->{"mt:liveStreams"}->{_embedded}->{"mt:items"}->{stream}->{streamUrl}
        };
    }

    return $publicationService;
}

sub _collectionFromJson {
    my $jsonCollection = shift;

    my $collection = {
        imageUrl => $jsonCollection->{_links}->{"mt:image"}->{href},
        title => $jsonCollection->{title},
        id => $jsonCollection->{id}
    };

    return $collection;
}

sub _programSetFromJson {
    my $jsonProgramSet = shift;

    my $programSet = {
        imageUrl => $jsonProgramSet->{_links}->{"mt:image"}->{href},
        title => $jsonProgramSet->{title},
        id => $jsonProgramSet->{id}
    };

    return $programSet;
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
    my $imageURL = shift;
    my $thumbnailSize = 4.0 * "$serverPrefs->{prefs}->{thumbSize}";

    $imageURL =~ s/{ratio}/1x1/i;
    $imageURL =~ s/{width}/$thumbnailSize/i;

    return $imageURL;
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
