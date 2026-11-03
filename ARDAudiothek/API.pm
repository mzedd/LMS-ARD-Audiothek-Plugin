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

use JSON::XS;
use Digest::MD5 qw(md5_hex);
use URI::Escape qw(uri_escape_utf8);

use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;

use Plugins::ARDAudiothek::GraphQLQueries;

use constant GRAPHQL_API_URL => 'https://api.ardaudiothek.de/graphql?query=';
use constant PLAYOUT_API_URL => 'https://api.ard.de/playout-api/v1/pages';
use constant TIMEOUT_IN_S => 20;
use constant CACHE_TTL_IN_S => 1 * 3600; # cache one hour

my $log = logger('plugin.ardaudiothek');
my $cache = Slim::Utils::Cache->new();
my $serverPrefs = preferences('server');
my %pendingRequests;

sub search {
    my ($class, $callback, $args) = @_;

    my $url = GRAPHQL_API_URL . Plugins::ARDAudiothek::GraphQLQueries::SEARCH;
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

    _call(_playoutPageUrl('/'), sub {
        $callback->(_playoutSectionsToLists(shift));
    });
}

sub getEditorialCategories {
    my ($class, $callback, $args) = @_;

    # The GraphQL editorialCategories connection is empty since the move to
    # ARD Sounds. Read the same rubric navigation as the current website.
    _call(_playoutPageUrl('/podcasts/'), sub {
        my $sections = _playoutSectionsToLists(shift);
        my @categories;

        for my $section (@{$sections}) {
            push @categories, @{$section->{items}}
                if $section->{type} eq 'editorialCategories';
        }

        $callback->(\@categories);
    });
}

sub getEditorialCategoryPlaylists {
    my ($class, $callback, $args) = @_;

    if($args->{id} =~ m{^/}) {
        _call(_playoutPageUrl($args->{id}), sub {
            $callback->(_playoutSectionsToLists(shift));
        });
        return;
    }

    my $url = GRAPHQL_API_URL .
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

    _call(_playoutPageUrl('/radio/sender/'), sub {
        my $sections = _playoutSectionsToLists(shift);
        my @organizations;
        for my $section (@{$sections}) {
            next unless $section->{type} eq 'publicationServices';
            push @organizations, {
                name => $section->{title},
                publicationServices => [map {
                    {id => $_->{id}, name => $_->{title}, imageUrl => $_->{imageUrl}}
                } @{$section->{items}}]
            };
        }
        $callback->(\@organizations);
    });
}

sub getPublicationService {
    my ($class, $callback, $args) = @_;

    if($args->{id} =~ m{^/radio/}) {
        _call(_playoutPageUrl($args->{id}), sub {
            $callback->({sections => _playoutSectionsToLists(shift)});
        });
        return;
    }
    my $url = GRAPHQL_API_URL . replaceIdInQuery(
        Plugins::ARDAudiothek::GraphQLQueries::PUBLICATION_SERVICE, $args->{id}
    );

    _call($url, sub {
        my $content = shift;
        $callback->(_publicationServiceFromJson($content->{data}->{publicationService}));
    });
}

sub getProgramSet {
    my ($class, $callback, $args) = @_;

    my $url = GRAPHQL_API_URL . replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::PROGRAM_SET, $args->{id});
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

    my $url = GRAPHQL_API_URL . replaceIdInQuery(Plugins::ARDAudiothek::GraphQLQueries::EDITORIAL_COLLECTION, $args->{id});
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

    if(my $episode = $cache->get('ardaudiothek:episode:' . $args->{id})) {
        $callback->($episode);
        return;
    }

    my $query = Plugins::ARDAudiothek::GraphQLQueries::EPISODE;
    if($args->{id} =~ /^urn:ard:(permanent|event)-livestream:/) {
        my $streamType = $1 eq 'permanent' ? 'permanentLivestream' : 'eventLivestream';
        $query = Plugins::ARDAudiothek::GraphQLQueries::LIVESTREAM;
        $query =~ s/\$streamType/$streamType/;
    }
    my $url = GRAPHQL_API_URL . replaceIdInQuery($query, $args->{id});

    my $adapter = sub {
        my $jsonEpisode = shift;

        $callback->(_episodeFromJson($jsonEpisode->{data}->{item}));
    };

    _call($url, $adapter);

    return;
}

sub clearCache {
    $cache->cleanup();
}

sub _playoutPageUrl {
    my $path = shift;
    return PLAYOUT_API_URL . '?canonicalWebURL=' . uri_escape_utf8($path) . '&embedded=all';
}

sub _playoutSectionsToLists {
    my $content = shift;
    my @sections;

    for my $widget (@{$content->{widgets} || []}) {
        my @items;
        my $sectionType;

        for my $teaser (@{$widget->{teasers} || []}) {
            my $target = $teaser->{target} || {};
            my $id = $teaser->{assetId} || $target->{assetId} || $target->{pageId} || '';
            my $path = $target->{url} || '';
            my ($type, $item);
            my $image = $teaser->{squareImage} || $teaser->{image} || {};
            my $meta = {
                id => $id,
                title => $teaser->{title},
                imageUrl => $image->{templateURL} || $teaser->{publisher}->{logo1x1Colored}
            };

            if($id =~ /^urn:ard:show:/) {
                $type = 'programSets';
                $item = $meta;
            }
            elsif($id =~ /^urn:ard:episode:/) {
                $type = 'episodes';
                $item = {
                    %{$meta},
                    duration => $teaser->{duration},
                    description => $teaser->{description},
                    show => $teaser->{showTitle},
                    url => $teaser->{assetDownloadURL}
                };
            }
            elsif($id =~ /^urn:ard:(?:permanent|event)-livestream:/) {
                $type = 'livestreams';
                $item = $meta;
            }
            elsif($path =~ m{^/radio/}) {
                $type = 'publicationServices';
                $item = { %{$meta}, id => $path };
            }
            elsif($path =~ m{^/(?:rubrik|sammlung)/}) {
                $type = 'editorialCategories';
                $item = { %{$meta}, id => $path };
            }
            else {
                next;
            }

            $sectionType = defined $sectionType && $sectionType ne $type ? 'mixed' : $type;
            push @items, {type => $type, item => $item};
        }

        next unless @items;
        push @sections, {
            title => $widget->{title} || $widget->{seo}->{title} || 'Podcasts',
            type => $sectionType,
            items => $sectionType eq 'mixed' ? \@items : [map {$_->{item}} @items]
        };
    }

    return \@sections;
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
        }

        # exclude sections without a title from our list
        if($section->{title} eq "") {
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
        id => $jsonCategory->{coreId}
    };

    return $category;
}

sub _organizationFromJson {
    my $jsonOrganization = shift;

    my $organization = {
        name => $jsonOrganization->{title},
        publicationServices => _itemlistFromJson(
            $jsonOrganization->{publicationServicesByOrganizationName}->{nodes},
            \&_publicationServiceMetaFromJson
        )
    };

    return $organization;
}

sub _publicationServiceMetaFromJson {
    my $service = shift;
    return {
        id => $service->{coreId},
        name => $service->{title},
        imageUrl => $service->{image}->{url1X1}
    };
}

sub _publicationServiceFromJson {
    my $jsonPublicationService = shift;

    my $publicationService = {
        id => $jsonPublicationService->{coreId},
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
        id => $jsonPlaylist->{coreId}
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
    return undef unless ref $jsonEpisode eq 'HASH' && ($jsonEpisode->{assetId} || $jsonEpisode->{coreId});

    my $episode = {
        url => $jsonEpisode->{audios}[0]->{url},
        imageUrl => $jsonEpisode->{image}->{url1X1},
        duration => $jsonEpisode->{duration},
        id => $jsonEpisode->{assetId} || $jsonEpisode->{coreId},
        description => $jsonEpisode->{summary},
        title => $jsonEpisode->{title},
        show => $jsonEpisode->{programSet}->{title}
    };

    # List responses already contain the fields needed for playback and metadata.
    # Share them with getEpisode instead of fetching every item again.
    if($episode->{url}) {
        my $cacheKey = 'ardaudiothek:episode:' . $episode->{id};
        $cache->set($cacheKey, $episode, CACHE_TTL_IN_S)
            unless $cache->get($cacheKey);
    }

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

    if(exists $pendingRequests{$cacheKey}) {
        push @{$pendingRequests{$cacheKey}}, $callback;
        return undef;
    }
    $pendingRequests{$cacheKey} = [$callback];

    Slim::Networking::SimpleAsyncHTTP->new(
        sub {
            my $response = shift;

            my $content = eval { decode_json($response->content) };
            if($@ || ref $content ne 'HASH') {
                $log->error("Invalid JSON response calling $url.");
                _finishCall($cacheKey, undef);
                return;
            }

            my $hasErrors = $content->{errors} && @{$content->{errors}};
            if($hasErrors) {
                my $errors = join('; ', map { $_->{message} || 'Unknown GraphQL error' } @{$content->{errors}});
                $log->error("GraphQL error calling $url: $errors");
                unless(ref $content->{data} eq 'HASH' && grep { defined $_ } values %{$content->{data}}) {
                    _finishCall($cacheKey, undef);
                    return;
                }
            }

            # GraphQL can return useful data alongside a failed optional field.
            # Deliver that data, but allow the next call to retry missing parts.
            $cache->set($cacheKey, $content, CACHE_TTL_IN_S) unless $hasErrors;

            _finishCall($cacheKey, $content);
        },
        sub {
            $log->error("An error occured calling $url.");
            _finishCall($cacheKey, undef);
        },
        { timeout => TIMEOUT_IN_S }
    )->get($url);

    return undef;
}

sub _finishCall {
    my ($cacheKey, $content) = @_;
    my $callbacks = delete $pendingRequests{$cacheKey} || [];

    for my $callback (@{$callbacks}) {
        eval { $callback->($content) };
        $log->error("API callback failed: $@") if $@;
    }
}

1;
