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

    Slim::Menu::TrackInfo->registerInfoProvider( ardaudiothek => (
            after => 'top',
            func  => \&trackInfoMenu
        )
    );
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

    $callback->([
            { name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES') , type => 'link', url => \&listEditorialCategories },
            { name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_SEARCH'), type => 'search', url => \&searchItems }
    ]);
}

sub searchItems {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $content = shift;
            
            my $items = [];
            my $numberOfElements = $content->{numberOfElements}; 

            for my $entry (@{$content->{_embedded}->{"mt:items"}}) {
                my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});
                
                push @{$items}, {
                    name => $entry->{title},
                    type => 'audio',
                    url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    favorites_type => 'link',
                    favorites_url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    play => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    on_select => 'play',
                    image => $imageURL
                };
            }
            
            $callback->({ items => $items, offset => $args->{index}, total => $numberOfElements });
        },
        {
            searchType  => 'items',
            searchWord  => $args->{search},
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

    $log->info(Data::Dump::dump($params));

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES_MENU_MOSTPLAYED'),
        type => 'link',
        url => \&listMostPlayedEpisodes,
        passthrough => [ {editorialCategoryID => $params->{editorialCategoryID}} ]
    };

    push @items, {
        name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES_MENU_NEWEST'),
        type => 'link',
        url => \&listNewestEpisodes,
        passthrough => [ {editorialCategoryID => $params->{editorialCategoryID}} ]
    };

    $callback->({items => \@items});
}

sub listMostPlayedEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->getEditorialCategoryPlaylists(
        sub {
            my $content = shift; 
            my $items = listEpisodes($content->{_embedded}->{"mt:mostPlayed"});
            $callback->({items => $items});
        },
        {
            editorialCategoryID => $params->{editorialCategoryID}
        }
    );
}

sub listNewestEpisodes {
    my ($client, $callback, $args, $params) = @_;

    Plugins::ARDAudiothek::API->getEditorialCategoryPlaylists(
        sub {
            my $content = shift;
            my $items = listEpisodes($content->{_embedded}->{"mt:items"});
            $callback->({items => $items});
        },
        {
            editorialCategoryID => $params->{editorialCategoryID}
        }
    );
}

sub listEpisodes {
    my $jsonEpisodeList = shift;
    my $items = [];

    for my $entry (@{$jsonEpisodeList}) {
        my $imageURL = selectImageFormat($entry->{_links}->{"mt:image"}->{href});
        
        push @{$items}, {
            name => $entry->{title},
            type => 'audio',
            url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
            favorites_type => 'link',
            favorites_url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
            play => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
            on_select => 'play',
            image => $imageURL
        };
    }

    return $items;
}

sub trackInfoMenu {
    my ($client, $url, $track, $remoteMeta) = @_;

    $log->info($url);
    $log->info(Data::Dump::dump($track));
    $log->info(Data::Dump::dump($remoteMeta));

    return;
}

sub selectImageFormat {
    my $imageURL = shift;
    my $thumbnailSize = 4.0 * "$serverPrefs->{prefs}->{thumbSize}";

    $imageURL =~ s/{ratio}/1x1/i;
    $imageURL =~ s/{width}/$thumbnailSize/i;

    return $imageURL;
}

1;
