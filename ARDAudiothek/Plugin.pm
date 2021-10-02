package Plugins::ARDAudiothek::Plugin;

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
use base qw(Slim::Plugin::OPMLBased);
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;

use Plugins::ARDAudiothek::API;

my $log = Slim::Utils::Log->addLogCategory( {
	category     => 'plugin.ardaudiothek',
	defaultLevel => 'WARN',
	description  => 'PLUGIN_ARDAUDIOTHEK_NAME',
	logGroups    => 'SCANNER',
} );
my $serverPrefs = preferences('server');

sub getDisplayName {
    return 'PLUGIN_ARDAUDIOTHEK_NAME'
}

sub initPlugin {
    my $class = shift;

    $class->SUPER::initPlugin(
        feed    => \&homescreen,
        tag     => 'ardaudiothek',
        menu    => 'radios',
        is_app  => 1,
        weight  => 10
    );

    Plugins::ARDAudiothek::API->clearCache();

    Slim::Player::ProtocolHandlers->registerHandler('ardaudiothek', 'Plugins::ARDAudiothek::ProtocolHandler');
}

sub shutdownPlugin {
    Plugins::ARDAudiothek::API->clearCache();
}

sub homescreen {
    my ($client, $callback) = @_;

    if(not defined $client) {
        $callback->([{ name => string('PLUGIN_ARDAUDIOTHEK_NO_PLAYER')}]);
        return;
    }

    my @items;

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_SEARCH'),
        type => 'search',
        url => \&search
    };

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_DISCOVER'),
        type => 'link',
        url => \&discover
    };

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ORGANIZATIONS'),
        type => 'link',
        url => \&organizations
    };
    
    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES'),
        type => 'link',
        url => \&editorialCategories
    };

    $callback->({ items => \@items});
}

sub search {
    my ($client, $callback, $args) = @_;
    my @items;

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_PROGRAMSETS'),
        type => 'link',
        url => \&searchProgramSets,
        passthrough => [{ search => $args->{search} }]
    };

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ITEMS'),
        type => 'link',
        url => \&searchEpisodes,
        passthrough => [{ search => $args->{search} }]
    };

    $callback->({ items => \@items });
}

sub searchProgramSets {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $programSetsSearchresult = shift;
           
            my $items = programSetsToOPML($programSetsSearchresult->{programSets});
            my $numberOfElements = $programSetsSearchresult->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            searchType  => 'programsets',
            searchWord  => $params->{search},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub searchEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $episodesSearchresult = shift;
            
            my $items = episodesToOPML($episodesSearchresult->{episodes});
            my $numberOfElements = $episodesSearchresult->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            searchType  => 'items',
            searchWord  => $params->{search},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub discover {
    my ($client, $callback) = @_;

    Plugins::ARDAudiothek::API->getDiscover(
        sub {
            my $content = shift;
            my @items;

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_STAGE'),
                type => 'link',
                items => episodesToOPML($content->{stageEpisodes})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_OUR_FAVORITES'),
                type => 'link',
                items => collectionsToOPML($content->{editorialCollections}) 
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_TOPICS'),
                type => 'link',
                items => collectionsToOPML($content->{featuredPlaylists})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_MOSTPLAYED'),
                type => 'link',
                items => episodesToOPML($content->{mostPlayedEpisodes})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'link',
                items => programSetsToOPML($content->{featuredProgramSets})
            };

            $callback->({items => \@items});
        }
    );
}

sub editorialCategories {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->getEditorialCategories(
        sub {
            my $categorylist = shift;
            my @items;
            
            for my $category (@{$categorylist}) {
                push @items, {
                    name => $category->{title},
                    type => 'link',
                    url => \&editorialCategoryPlaylists,
                    image => Plugins::ARDAudiothek::API::selectImageFormat($category->{imageUrl}),
                    passthrough => [ {id => $category->{id}} ]
                }
            }

            $callback->({items => \@items});
        }
    );
}

sub editorialCategoryPlaylists {
    my ($client, $callback, $args, $params) = @_;
    my @items;

    Plugins::ARDAudiothek::API->getEditorialCategoryPlaylists(
        sub {
            my $editorialCategoryPlaylists = shift;

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_MOSTPLAYED'),
                type => 'link',
                items => episodesToOPML($editorialCategoryPlaylists->{mostPlayedEpisodes})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_NEWEST'),
                type => 'link',
                items => episodesToOPML($editorialCategoryPlaylists->{newestEpisodes})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'link',
                items => programSetsToOPML($editorialCategoryPlaylists->{featuredProgramSets})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ALL_PROGRAMSETS'),
                type => 'link',
                items => programSetsToOPML($editorialCategoryPlaylists->{programSets})
            };

            $callback->({items => \@items});
        },
        {
            id => $params->{id}
        }
    );
}

sub organizations {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->getOrganizations(
        sub {
            my $organizationlist = shift;
            my @items;

            for my $organization (@{$organizationlist}) { 
                push @items, {
                    name => $organization->{name},
                    type => 'link',
                    items => publicationServices($organization->{publicationServices})
                };
            }

            $callback->({items => \@items});
        }
    );
}

sub publicationServices {
    my $publicationServices = shift;
    my @items;

    for my $publicationService (@{$publicationServices}) {
        my $publicationServiceItems = programSetsToOPML($publicationService->{programSets});
       
        # add radio station if there is one
        if(defined $publicationService->{liveStream}) {
            my $liveStream = $publicationService->{liveStream};

            unshift @{$publicationServiceItems}, {
                name => $liveStream->{name},
                type => 'audio',
                image => Plugins::ARDAudiothek::API::selectImageFormat($liveStream->{imageUrl}),
                play => $liveStream->{url}
            };
        }

        push @items, {
            name => $publicationService->{name},
            type => 'link',
            image => Plugins::ARDAudiothek::API::selectImageFormat($publicationService->{imageUrl}),
            items => $publicationServiceItems
        };
    }

    return \@items;
}

sub programSetsToOPML {
    my $programSetlist = shift;
    my @items;

    for my $programSet (@{$programSetlist}) {
        push @items, {
            name => $programSet->{title},
            type => 'playlist',
            image => Plugins::ARDAudiothek::API::selectImageFormat($programSet->{imageUrl}),
            url => \&programSetEpisodes,
            favorites_url => 'ardaudiothek://programset/' . $programSet->{id},
            passthrough => [{id => $programSet->{id}}]
       };
    }

    return \@items;
}

sub programSetEpisodes {
    my ($client, $callback, $args, $params) = @_;
    
    Plugins::ARDAudiothek::API->getProgramSet(
        sub {
            my $programSet = shift;

            my $items = episodesToOPML($programSet->{episodes}); 
            my $numberOfElements = $programSet->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            id => $params->{id},
            offset => $args->{index},
            limit => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub collectionsToOPML {
    my $collectionlist = shift;
    my @items;

    for my $collection (@{$collectionlist}) {
        push @items, {
            name => $collection->{title},
            type => 'playlist',
            image => Plugins::ARDAudiothek::API::selectImageFormat($collection->{imageUrl}),
            url => \&collectionEpisodes,
            favorites_url => 'ardaudiothek://collection/' . $collection->{id},
            passthrough => [{id => $collection->{id}}]
        };
    }

    return \@items;
}

sub collectionEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->getPlaylist(
        sub {
            my $collection = shift;

            my $items = episodesToOPML($collection->{episodes});
            my $numberOfElements = $collection->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            type => 'collection',
            id => $params->{id},
            offset => $args->{index},
            limit => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub episodesToOPML {
    my $episodelist = shift;
    my @items;

    for my $episode (@{$episodelist}) {
        push @items, {
            name => $episode->{title},
            type => 'audio',
            favorites_type => 'audio',
            play => 'ardaudiothek://episode/' . $episode->{id},
            on_select => 'play',
            image => Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl}),
            description => $episode->{description},
            duration => $episode->{duration},
            line1 => $episode->{title},
            line2 => $episode->{id}
        };
    }

    return \@items;
}

1;
