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
use constant API_QUERY_URL => API_URL . 'graphql?query=';
use constant TIMEOUT_IN_S => 20;
use constant CACHE_TTL_IN_S => 1 * 3600; # cache one hour

my $log = logger('plugin.ardaudiothek');
my $cache = Slim::Utils::Cache->new();
my $serverPrefs = preferences('server');

sub search {
    my ($class, $callback, $args) = @_;

    my $url = API_QUERY_URL . Plugins::ARDAudiothek::GraphQLQueries::SEARCH;
    $url =~ s/\$query/$args->{search}/i;
    $url =~ s/\$offset/$args->{offset}/i;
    $url =~ s/\$limit/$args->{limit}/i;

    my $adapter = sub {
        my $content = shift;
        $content = $content->{data}->{search};

        my $programSets = _itemlistFromJson(
            $content->{programSets}->{nodes},
            \&_playlistMetaFromJson
        );

        my $editorialCategories = _itemlistFromJson(
            $content->{editorialCategories}->{nodes},
            \&_categoryFromJson
        );

        my $editorialCollections = _itemlistFromJson(
            $content->{editorialCollections}->{nodes},
            \&_playlistMetaFromJson
        );

        my $episodes = _itemlistFromJson(
            $content->{items}->{nodes},
            \&_episodeFromJson
        );

        my $searchResults = {
            programSets => $programSets,
            editorialCategories => $editorialCategories,
            editorialCollections => $editorialCollections,
            episodes => $episodes
        };

        $callback->($searchResults);
    };

    _call($url, $adapter);
}

sub getDiscover {
    my ($class, $callback, $args) = @_;

    my $url = API_QUERY_URL . Plugins::ARDAudiothek::GraphQLQueries::DISCOVER;

    my $adapter = sub {
        my $content = shift;
        $content = $content->{data}->{homescreen};
        my @items;
 
        for my $section (@{$content->{sections}}) {
            if($section->{type} eq "STAGE") {
                push (@items, {
                        title => "Entdecken",
                        items => _itemlistFromJson($section->{nodes}, \&_episodeFromJson),
                        type => "episodes"
                    }
                );
                next;
            }

            if($section->{type} eq "featured_programset") {
                push (@items, {
                        title => $section->{title},
                        items => _itemlistFromJson($section->{nodes}, \&_playlistMetaFromJson),
                        type => "programSets"
                    }
                );
                next;
            }

            if($section->{type} eq "GRID_LIST") {
                push (@items, {
                        title => $section->{title},
                        items => _itemlistFromJson($section->{nodes}, \&_playlistMetaFromJson),
                        type => "editorialCollections"
                    }
                );
                next;
            }
        }

        $callback->(\@items);
    };

    _call($url, $adapter);
}

sub getEditorialCategories {
    my ($class, $callback, $args) = @_;
    my $url = API_QUERY_URL . Plugins::ARDAudiothek::GraphQLQueries::EDITORIAL_CATEGORIES;

    my $adapter = sub {
        my $content = shift;

        my $categorylist = _itemlistFromJson(
            $content->{data}->{editorialCategories}->{nodes},
            \&_categoryFromJson
        );
        
        $callback->($categorylist);
    };

    _call($url, $adapter);
}

sub getEditorialCategoryPlaylists {
    my ($class, $callback, $args) = @_;
    my $url = API_QUERY_URL .
        replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::EDITORIAL_CATEGORY_PLAYLISTS, $args->{id});

    my $adapter = sub {
        my $content = shift;
        $content = $content->{data}->{editorialCategory};

        my $mostPlayedEpisodes = _itemlistFromJson(
            $content->{sections}[0]->{nodes},
            \&_episodeFromJson
        );

        my $newestEpisodes = _itemlistFromJson(
            $content->{sections}[1]->{nodes},
            \&_episodeFromJson
        );

        my $featuredProgramSets = _itemlistFromJson(
            $content->{sections}[2]->{nodes},
            \&_playlistMetaFromJson
        );

        my $programSets = _itemlistFromJson(
            $content->{sections}[3]->{nodes},
            \&_playlistMetaFromJson
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

sub getOrganizations {
    my ($class, $callback, $args) = @_;
    my $url = API_QUERY_URL . Plugins::ARDAudiothek::GraphQLQueries::ORGANIZATIONS;

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

sub getProgramSet {
    my ($class, $callback, $args) = @_;

    my $url = API_QUERY_URL . replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::PROGRAM_SET, $args->{id});
    $url =~ s/\$offset/$args->{offset}/i;
    $url =~ s/\$limit/$args->{limit}/i;

    my $adapter = sub {
        my $jsonProgramSet = shift;
        my $programSet = _playlistFromJson($jsonProgramSet->{data}->{programSet});
        $callback->($programSet);
    };

    _call($url, $adapter);
}

sub getEditorialCollection {
    my ($class, $callback, $args) = @_;

    my $url = API_QUERY_URL . replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::EDITORIAL_COLLECTION, $args->{id});
    $url =~ s/\$limit/$args->{limit}/i;
    $url =~ s/\$offset/$args->{offset}/i;
    
    $log->error($url);

    my $adapter = sub {
        my $jsonProgramSet = shift;
        my $programSet = _editorialCollectionFromJson($jsonProgramSet->{data}->{editorialCollection});
        $callback->($programSet);
    };

    _call($url, $adapter);
}

sub getEpisode {
    my ($class, $callback, $args) = @_;

    my $url = API_QUERY_URL . replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::EPISODE, $args->{id});
    
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
        name => $jsonOrganization->{title},
        publicationServices => _itemlistFromJson(
            $jsonOrganization->{publicationServicesByOrganizationName}->{nodes},
            \&_publicationServiceFromJson
        )
    };

    return $organization;
}

sub _publicationServiceFromJson {
    my $jsonPublicationService = shift;

    my $publicationService = {
        name => $jsonPublicationService->{title},
        imageUrl => $jsonPublicationService->{image}->{url},
        programSets => _itemlistFromJson(
            $jsonPublicationService->{programSets}->{nodes},
            \&_playlistMetaFromJson
        )
    };

    # if there are livestreams, add them
    if($jsonPublicationService->{permanentLivestreams}->{totalCount} > 0) {
        my @permanentLivestreams;

        for my $jsonPermanentLivestream (@{$jsonPublicationService->{permanentLivestreams}->{nodes}}) {
            push @permanentLivestreams, {
                title => $jsonPermanentLivestream->{title},
                imageUrl => $jsonPermanentLivestream->{image}->{url},
                url => $jsonPermanentLivestream->{audios}[0]->{url}
            };
        }
        $publicationService->{permanentLivestreams} = \@permanentLivestreams;
    }

    return $publicationService;
}

sub _playlistMetaFromJson {
    my $jsonPlaylist = shift;

    my $playlist = {
        imageUrl => $jsonPlaylist->{image}->{url},
        title => $jsonPlaylist->{title},
        id => $jsonPlaylist->{id}
    };

    return $playlist;
}

sub _playlistFromJson {
    my $jsonPlaylist = shift;

    my $playlist = {
        numberOfElements => $jsonPlaylist->{numberOfElements},
        episodes => _itemlistFromJson($jsonPlaylist->{items}->{nodes}, \&_episodeFromJson)
    };
}

sub _editorialCollectionFromJson {
    my $jsonPlaylist = shift;

    my $playlist = {
        numberOfElements => $jsonPlaylist->{numberOfElements},
        episodes => _itemlistFromJson($jsonPlaylist->{items}->{nodes}, \&_episodeFromJson)
    };
}

sub _episodeFromJson {
    my $jsonEpisode = shift;

    my $episode = {
        url => $jsonEpisode->{audios}[0]->{url},
        imageUrl => $jsonEpisode->{image}->{url},
        duration => $jsonEpisode->{duration},
        id => $jsonEpisode->{id},
        description => $jsonEpisode->{summary},
        title => $jsonEpisode->{title},
        show => $jsonEpisode->{programSet}->{title}
    };

    return $episode;
}

sub selectImageFormat {
    my $imageUrl = shift;
    my $thumbnailSize = 2.0 * $serverPrefs->{prefs}->{thumbSize};

    $imageUrl =~ s/{ratio}/1x1/i; # for compability
    $imageUrl =~ s/16x9/1x1/i;
    $imageUrl =~ s/{width}/$thumbnailSize/i;

    return $imageUrl;
}

sub replaceIdInQuery {
    my ($query, $id) = @_;
    
    $query =~ s/\$id/$id/i;
    
    return $query;
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
