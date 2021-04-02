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
                items => listEpisodes($content->{_embedded}->{"mt:stageItems"}->{_embedded}->{"mt:items"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_OUR_FAVORITES'),
                type => 'link',
                items => listCollections($content->{_embedded}->{"mt:editorialCollections"}->{_embedded}->{"mt:editorialCollections"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_TOPICS'),
                type => 'link',
                items => listCollections($content->{_embedded}->{"mt:featuredPlaylists"}->{_embedded}->{"mt:editorialCollections"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_MOSTPLAYED'),
                type => 'link',
                items => listEpisodes($content->{_embedded}->{"mt:mostPlayed"}->{_embedded}->{"mt:items"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'items',
                items => listProgramSet($content->{_embedded}->{"mt:featuredProgramSets"}->{_embedded}->{"mt:programSets"})
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
            
            my $items = listProgramSet($content->{_embedded}->{"mt:programSets"});
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
            
            my $items = listEpisodes($content->{_embedded}->{"mt:items"});
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
            my $content = shift;

            my $items = [];
            
            for my $entry (@{$content->{_embedded}->{"mt:editorialCategories"}}) {
                my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});

                push @{$items}, {
                    name => $entry->{title},
                    type => 'link',
                    url => \&listEditorialCategoryMenus,
                    image => $imageURL,
                    passthrough => [ {editorialCategoryID => $entry->{id}} ]
                }
            }

            $callback->({items => $items});
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
                items => listEpisodes($content->{_embedded}->{"mt:mostPlayed"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_NEWEST'),
                type => 'link',
                items => listEpisodes($content->{_embedded}->{"mt:items"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_FEATURED_PROGRAMSETS'),
                type => 'link',
                items => listProgramSet($content->{_embedded}->{"mt:featuredProgramSets"})
            };

            push @items, {
                name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_ALL_PROGRAMSETS'),
                type => 'link',
                items => listProgramSet($content->{_embedded}->{"mt:programSets"})
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
            my $content = shift;
            my $items;

            for my $entry (@{$content->{_embedded}->{"mt:organizations"}}) { 
                push @{$items}, {
                    name => $entry->{name},
                    type => 'link',
                    items => listPublicationServices($entry->{_embedded}->{"mt:publicationServices"})
                };
            }

            $callback->({items => $items});
        }
    );
}

sub listPublicationServices {
    my $jsonPublicationServices = shift;
    my $items = [];

    if(ref $jsonPublicationServices eq ref {}) {
        my $imageURL = selectImageFormat($jsonPublicationServices->{_links}->{"mt:image"}->{href});

        push @{$items}, {
            name => $jsonPublicationServices->{title},
            type => 'link',
            image => $imageURL,
            items => publicationServiceDetails($jsonPublicationServices)
        }
    } else {
        for my $entry (@{$jsonPublicationServices}) {
            my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});
            
            push @{$items}, {
                name => $entry->{title},
                type => 'link',
                image => $imageURL,
                items => publicationServiceDetails($entry)
            };
        }
    }

    return $items;
}

sub publicationServiceDetails {
    my $content = shift;
    my $items = [];

    $items = listProgramSet($content->{_embedded}->{"mt:programSets"});

    if($content->{_embedded}->{"mt:liveStreams"}->{numberOfElements} == 1) {
       my $imageURL = selectImageFormat($content->{_links}->{"mt:image"}->{href});
       unshift @{$items}, {
           name => 'Livestream',
           type => 'audio',
           play => $content->{_embedded}->{"mt:liveStreams"}->{_embedded}->{"mt:items"}->{stream}->{streamUrl},
           image => $imageURL
       };
    }

    return $items;
}

sub listProgramSet {
    my $jsonProgramSet = shift;
    my $items = [];

    if(ref $jsonProgramSet eq ref {}) {
        my $imageURL = selectImageFormat($jsonProgramSet->{_links}->{"mt:image"}->{href});
        
        push @{$items}, {
            name  => $jsonProgramSet->{title},
            type  => 'link',
            image => $imageURL,
            url => \&programSetDetails,
            passthrough => [{programSetID => $jsonProgramSet->{id}}]
        };
    } else {
        for my $entry (@{$jsonProgramSet}) {
            my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});
            
            push @{$items}, {
                name => $entry->{title},
                type => 'link',
                image => $imageURL,
                url => \&programSetDetails,
                passthrough => [{programSetID => $entry->{id}}]
            };
        }
    }

    return $items;
}

sub programSetDetails {
    my ($client, $callback, $args, $params) = @_;
    
    Plugins::ARDAudiothek::API->getProgramSet(
        sub {
            my $content = shift;

            my $items = listEpisodes($content->{_embedded}->{"mt:items"});
            my $numberOfElements = $content->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            programSetID => $params->{programSetID},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub listCollections {
    my $jsonCollections = shift;
    my $items = [];

    for my $entry (@{$jsonCollections}) {
        my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});
        
        push @{$items}, {
            name => $entry->{title},
            type => 'link',
            image => $imageURL,
            url => \&listCollectionEpisodes,
            passthrough => [{collectionID => $entry->{id}}]
        };
    }

    return $items;
}

sub listCollectionEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->getCollectionContent(
        sub {
            my $content = shift;

            my $items = listEpisodes($content->{_embedded}->{"mt:items"});
            my $numberOfElements = $content->{numberOfElements}; 
           
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            collectionID => $params->{collectionID},
            offset      => $args->{index},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub listEpisodes {
    my $jsonEpisodeList = shift;
    my $items = [];

    for my $entry (@{$jsonEpisodeList}) {
        my $episode = episodeDetails($entry);

        push @{$items}, {
            name => $episode->{title},
            type => 'audio',
            favorites_type => 'audio',
            play => 'ardaudiothek://episode/' . $episode->{id},
            on_select => 'play',
            image => selectImageFormat($episode->{image}),
            description => $episode->{description},
            duration => $episode->{duration},
            line1 => $episode->{title},
            line2 => $episode->{show}
        };
    }

    return $items;
}

sub episodeDetails {
    my $item = shift;

    my %episode = (
        url => $item->{_links}->{"mt:bestQualityPlaybackUrl"}->{href}, 
        image => $item->{_links}->{"mt:image"}->{href},
        duration => $item->{duration},
        id => $item->{id},
        description => $item->{synopsis},
        title => $item->{title},
        show => $item->{_embedded}->{"mt:programSet"}->{title}
    );

    return \%episode;
}

sub selectImageFormat {
    my $imageURL = shift;
    my $thumbnailSize = 4.0 * "$serverPrefs->{prefs}->{thumbSize}";

    $imageURL =~ s/{ratio}/1x1/i;
    $imageURL =~ s/{width}/$thumbnailSize/i;

    return $imageURL;
}

1;
