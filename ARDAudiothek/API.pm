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
        my $items = _sectionsToLists($content->{data}->{homescreen});
        $callback->($items);
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
        my $items = _sectionsToLists($content->{data}->{editorialCategory});
        $callback->($items);
    };

    _call($url, $adapter);
}

sub getOrganizations {
    my ($class, $callback, $args) = @_;
    my $url = API_QUERY_URL . Plugins::ARDAudiothek::GraphQLQueries::ORGANIZATIONS;

    my $adapter = sub {
        my $content = shift;

        # remove the last 7 elements, because they contain no content
        splice(@{$content->{data}->{organizations}->{nodes}}, 14);

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
    
    my $adapter = sub {
        my $jsonEditorialCollection = shift;
        my $editorialCollection = _playlistFromJson($jsonEditorialCollection->{data}->{editorialCollection});
        $callback->($editorialCollection);
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

sub _sectionsToLists {
    my $content = shift;
    my @items;

    for my $section (@{$content->{sections}}) {
        # filter out sections without nodes
        my $numberOfElements = @{$section->{nodes}};
        if($numberOfElements eq 0) {
            next;
        }

        if($section->{type} eq "STAGE" or $section->{type} eq "newest_episodes" or $section->{type} eq "most_played" or $section->{type} eq "featured_item") {
            push (@items, {
                    title => (defined $section->{title}) ? $section->{title} : "Entdecken",
                    items => _itemlistFromJson($section->{nodes}, \&_episodeFromJson),
                    type => "episodes"
                }
            );
            next;

        # exclude sections without a title from our list
        }if($section->{title} eq "") {
              next;
        }
        
        if($section->{type} eq "program_sets" or $section->{type} eq "featured_programset") {
            push (@items, {
                    title => $section->{title},
                    items => _itemlistFromJson($section->{nodes}, \&_playlistMetaFromJson),
                    type => "programSets"
                }
            );
            next;
        }

        if($section->{nodeTypes}[0] eq "EditorialCategory") {
            push (@items, {
                    title => $section->{title},
                    items => _itemlistFromJson($section->{nodes}, \&_categoryFromJson),
                    type => "editorialCategories"
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

    return \@items;
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
            my $item = $itemFromJson->($jsonItem);
            if(defined $item) {
                push (@itemlist, $item);
            }
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
        imageUrl => $jsonPublicationService->{image}->{url1X1},
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
                imageUrl => $jsonPermanentLivestream->{image}->{url1X1},
                url => $jsonPermanentLivestream->{audios}[0]->{url}
            };
        }
        $publicationService->{permanentLivestreams} = \@permanentLivestreams;
    }

    return $publicationService;
}

sub _playlistMetaFromJson {
    my $jsonPlaylist = shift;

    if($jsonPlaylist->{numberOfElements} == 0) {
        return undef;
    }

    my $playlist = {
        imageUrl => $jsonPlaylist->{image}->{url1X1},
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

sub _episodeFromJson {
    my $jsonEpisode = shift;

    my $episode = {
        url => $jsonEpisode->{audios}[0]->{url},
        imageUrl => $jsonEpisode->{image}->{url1X1},
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
    my $thumbnailSize = 10.0 * $serverPrefs->{prefs}->{thumbSize};

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
