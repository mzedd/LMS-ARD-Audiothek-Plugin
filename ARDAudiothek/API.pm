package Plugins::ARDAudiothek::API;

# ARD Audiothek Plugin for the Logitech Media Server (LMS)
# Copyright (C) 2021  Max Zimmermann  software@maxzimmermann.xyz
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use strict;

use JSON::XS::VersionOneAndTwo;
use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;

use Plugins::ARDAudiothek::GraphQLQueries;

use constant API_URL => 'https://api.ardaudiothek.de/';
use constant TIMEOUT_IN_S => 20;
use constant CACHE_TTL_IN_S => 1 * 3600; # cache one hour

my $log = logger('plugin.ardaudiothek');
my $cache = Slim::Utils::Cache->new();
my $serverPrefs = preferences('server');

sub getDiscover {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . Plugins::ARDAudiothek::GraphQLQueries::HOMESCREEN;

    my $adapter = sub {
        my $content = shift;
        $content = $content->{data}->{homescreen};

        my $stageEpisodes = _itemlistFromJson(
            $content->{sections}[0]->{items},
            \&_episodeFromJson
        );
        
        my $editorialCollections = _itemlistFromJson(
            $content->{sections}[1]->{editorialCollections},
            \&_playlistFromJson
        );

        my $featuredPlaylists = _itemlistFromJson(
            $content->{sections}[2]->{editorialCollections},
            \&_playlistFromJson);

        my $mostPlayedEpisodes = _itemlistFromJson(
            $content->{sections}[3]->{items},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{sections}[4]->{programSets},
            \&_playlistFromJson
        );

        my $discover = {
            stageEpisodes => $stageEpisodes,
            editorialCollections => $editorialCollections,
            featuredPlaylists => $featuredPlaylists,
            mostPlayedEpisodes => $mostPlayedEpisodes,
            featuredProgramSets => $featuredProgramSets
        };

        $callback->($discover);
    };

    _call($url, $adapter);
}

sub getEditorialCategories {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . Plugins::ARDAudiothek::GraphQLQueries::EDITORIAL_CATEGORIES;

    my $adapter = sub {
        my $content = shift;

        my $categorylist = _itemlistFromJson($content->{data}->{editorialCategories}->{nodes}, \&_categoryFromJson);
        
        $callback->($categorylist);
    };

    _call($url, $adapter);
}

sub getEditorialCategoryPlaylists {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . 'graphql/editorialcategoriesbyid/' . $args->{id};

    my $adapter = sub {
        my $content = shift;
        $content = $content->{data}->{rootEdCatById};

        my $mostPlayedEpisodes = _itemlistFromJson(
            $content->{sections}[1]->{items},
            \&_episodeFromJson
        );

        my $newestEpisodes = _itemlistFromJson(
            $content->{sections}[2]->{items},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{sections}[3]->{programSets},
            \&_playlistFromJson
        );

        my $programSets = _itemlistFromJson(
            $content->{sections}[4]->{programSets},
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

    my $url = API_URL . 'graphql/';
    my $adapter;

    if($args->{type} eq 'programset') {
        $url = $url . "programsets/$args->{id}";
        
        $adapter = sub {
            my $jsonPlaylist = shift;
            $jsonPlaylist = $jsonPlaylist->{data}->{programSet};

            my $playlist = {
                title => $jsonPlaylist->{title},
                id => $jsonPlaylist->{id},
                numberOfElements => $jsonPlaylist->{numberOfElements},
                description => $jsonPlaylist->{synopsis},
                episodes => _itemlistFromJson($jsonPlaylist->{items}->{nodes}, \&_episodeFromJson)
            };

            $callback->($playlist);
        };
    }
    elsif($args->{type} eq 'collection') {
        $url = $url . "editorialcollections/$args->{id}";

        $adapter = sub {
            my $jsonPlaylist = shift;
            $jsonPlaylist = $jsonPlaylist->{data}->{root};

            my $playlist = {
                title => $jsonPlaylist->{title},
                id => $jsonPlaylist->{id},
                numberOfElements => $jsonPlaylist->{numberOfElements},
                description => $jsonPlaylist->{synopsis},
                episodes => _itemlistFromJson($jsonPlaylist->{items}->{nodes}, \&_episodeFromJson)
            };

            $callback->($playlist);
        };
    }
    else {
        $callback->(undef);
    }

    _call($url, $adapter);
}

sub getProgramSet {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . Plugins::ARDAudiothek::GraphQLQueries::PROGRAM_SET;
    $url =~ s/{id}/$args->{id}/i;
    $url =~ s/{count}/$args->{count}/i;
    $url =~ s/{offset}/$args->{offset}/i;

    my $adapter = sub {
        my $jsonProgramSet = shift;
        my $programSet = _programSetFromJson($jsonProgramSet->{data}->{programSet});
        $callback->($programSet);
    };

    _call($url, $adapter);
}

sub getOrganizations {
    my ($class, $callback, $args) = @_;
    my $url = API_URL . 'graphql/organizations';

    my $adapter = sub {
        my $content = shift;

        my $organizationlist = _itemlistFromJson(
            $content->{data}->{organizations}->{nodes},
            \&_organizationFromJson
        );

        $callback->($organizationlist);
    };

    _call($url, $adapter);
}

sub getEpisode {
    my ($class, $callback, $args) = @_;

    my $url = API_URL . 'graphql/items/' . $args->{id};

    my $adapter = sub {
        my $jsonEpisode = shift;

        $callback->(_episodeFromJson($jsonEpisode->{data}->{item}));
    };

    my $cached = _call($url, $adapter);
    return _episodeFromJson($cached->{data}->{item});
}

sub clearCache {
    $cache->cleanup();
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
        imageUrl => $jsonCategory->{image}->{url},
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
            $jsonOrganization->{publicationServices}->{nodes},
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
            $jsonPublicationService->{programSets}->{nodes},
            \&_playlistFromJson
        )
    };

    # if there is a liveStream - add it
    if($jsonPublicationService->{liveStreams}->{numberOfElements} >= 1) {
        my @liveStreamUrls;

        for my $liveStream (@{$jsonPublicationService->{liveStreams}->{items}}) {
            push (@liveStreamUrls, $liveStream->{stream}->{streamUrl});
        }

        $log->error(Data::Dump::dump(@liveStreamUrls));

        $publicationService->{liveStream} = {
            name => 'Livestream',
            url => \@liveStreamUrls
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

sub _programSetFromJson {
    my $jsonProgramSet = shift;

    my $programSet = {
        title => $jsonProgramSet->{title},
        id => $jsonProgramSet->{id},
        description => $jsonProgramSet->{summary},
        imageUrl => $jsonProgramSet->{image}->{url},
        episodes => _itemlistFromJson($jsonProgramSet->{items}->{nodes}, \&_episodeFromJson)
    };
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
        show => $jsonEpisode->{programSet}->{title}
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
        return $cached;
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

    return undef;
}

1;
