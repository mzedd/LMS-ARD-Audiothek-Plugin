package Plugins::ARDAudiothek::Plugin;

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

    Slim::Player::ProtocolHandlers->registerHandler('ardaudiothek', 'Plugins::ARDAudiothek::ProtocolHandler');
}

sub shutdownPlugin {
    Plugins::ARDAudiothek::API->clearCache();
}

sub homescreen {
    my ($client, $callback, $args) = @_;

    if(not defined $client) {
        $callback->([{ name => string('PLUGIN_ARDAUDIOTHEK_NO_PLAYER')}]);
        return;
    }

    my @items;

    Plugins::ARDAudiothek::API->getHomescreen(
        sub {
            my $content = shift;

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_SEARCH'),
                type => 'search',
                url => \&search
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES'),
                type => 'link',
                url => \&listEditorialCategories
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ORGANIZATIONS'),
                type => 'link',
                url => \&listOrganizations
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_DISCOVER'),
                type => 'link',
                items => episodelistToOPML($content->{discoverEpisodelist})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_OUR_FAVORITES'),
                type => 'link',
                items => collectionlistToOPML($content->{editorialCollections}) 
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_TOPICS'),
                type => 'link',
                items => collectionlistToOPML($content->{featuredPlaylists})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_MOSTPLAYED'),
                type => 'link',
                items => episodelistToOPML($content->{mostPlayedEpisodelist})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'link',
                items => programSetlistToOPML($content->{featuredProgramSets})
            };

            $callback->({ items => \@items});
        }
    );
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
        url => \&searchItems,
        passthrough => [{ search => $args->{search} }]
    };

    $callback->({ items => \@items });
}

sub searchProgramSets {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $content = shift;
           
            my $items = programSetlistToOPML($content->{programSetlist});
            my $numberOfElements = $content->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            searchType  => 'programsets',
            searchWord  => $params->{search},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub searchItems {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $content = shift;
            
            my $items = episodelistToOPML($content->{episodelist});
            my $numberOfElements = $content->{numberOfElements}; 
           
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

sub listEditorialCategories {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->getEditorialCategories(
        sub {
            my $categorylist = shift;
            my @items;
            
            for my $category (@{$categorylist}) {
                push @items, {
                    name => $category->{title},
                    type => 'link',
                    url => \&listEditorialCategoryMenus,
                    image => Plugins::ARDAudiothek::API::selectImageFormat($category->{imageUrl}),
                    passthrough => [ {editorialCategoryID => $category->{id}} ]
                }
            }

            $callback->({items => \@items});
        }
    );
}

sub listEditorialCategoryMenus {
    my ($client, $callback, $args, $params) = @_;
    my @items;

    Plugins::ARDAudiothek::API->getEditorialCategoryPlaylists(
        sub {
            my $content = shift;

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_MOSTPLAYED'),
                type => 'link',
                items => episodelistToOPML($content->{mostPlayedEpisodelist})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_NEWEST'),
                type => 'link',
                items => episodelistToOPML($content->{newestEpisodelist})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'link',
                items => programSetlistToOPML($content->{featuredProgramSets})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ALL_PROGRAMSETS'),
                type => 'link',
                items => programSetlistToOPML($content->{programSets})
            };

            $callback->({items => \@items});
        },
        {
            editorialCategoryID => $params->{editorialCategoryID}
        }
    );
}

sub listOrganizations {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->getOrganizations(
        sub {
            my $organizationlist = shift;
            my @items;

            for my $organization (@{$organizationlist}) { 
                push @items, {
                    name => $organization->{name},
                    type => 'link',
                    items => listPublicationServices($organization->{publicationServices})
                };
            }

            $callback->({items => \@items});
        }
    );
}

sub listPublicationServices {
    my $publicationServices = shift;
    my @items;

    for my $publicationService (@{$publicationServices}) {
        my $publicationServiceItems = programSetlistToOPML($publicationService->{programSets});
       
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

sub programSetDetails {
    my ($client, $callback, $args, $params) = @_;
    
    Plugins::ARDAudiothek::API->getProgramSet(
        sub {
            my $programSet = shift;

            my $items = episodelistToOPML($programSet->{episodelist}); 
            my $numberOfElements = $programSet->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            programSetID => $params->{programSetID},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub listCollectionEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->getCollectionContent(
        sub {
            my $collection = shift;

            my $items = episodelistToOPML($collection->{episodelist});
            my $numberOfElements = $collection->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            collectionID => $params->{collectionID},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub episodelistToOPML {
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
            line2 => $episode->{show}
        };
    }

    return \@items;
}

sub collectionlistToOPML {
    my $collectionlist = shift;
    my @items;

    for my $collection (@{$collectionlist}) {
        push @items, {
            name => $collection->{title},
            type => 'link',
            image => Plugins::ARDAudiothek::API::selectImageFormat($collection->{imageUrl}),
            url => \&listCollectionEpisodes,
            passthrough => [{collectionID => $collection->{id}}]
        };
    }

    return \@items;
}

sub programSetlistToOPML {
    my $programSetlist = shift;
    my @items;

    for my $programSet (@{$programSetlist}) {
        push @items, {
            name => $programSet->{title},
            type => 'link',
            image => Plugins::ARDAudiothek::API::selectImageFormat($programSet->{imageUrl}),
            url => \&programSetDetails,
            passthrough => [{programSetID => $programSet->{id}}]
       };
    }

    return \@items;
}

1;
