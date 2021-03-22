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
}

sub shutdownPlugin {
    Plugins::ARDAudiothek::API->clearCache();
}

sub homescreen {
    my ($client, $callback, $args) = @_;

    $callback->([
            { name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_EDITORIALCATEGORIES') , type => 'link', url => \&dummy },
            { name => cstring($client, 'PLUGIN_ARDAUDIOTHEK_SEARCH'), type => 'search', url => \&searchItems }
    ]);
}

sub searchItems {
    my ($client, $callback, $args) = @_;

    Plugins::ARDAudiothek::API->search(
        sub {
            my $content = shift;
            my $items = [];

            for my $entry (@{$content->{_embedded}->{"mt:items"}}) {
                push @{$items}, {
                    name => $entry->{title},
                    type => 'audio',
                    url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    favorites_type => 'link',
                    favorites_url => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    play => $entry->{_links}->{"mt:bestQualityPlaybackUrl"}->{href},
                    on_select => 'play'
                };
            }
            
            $callback->({ items => $items });
        },
        {
            searchType  => 'items',
            searchWord  => $args->{search},
            limit       => $serverPrefs->{prefs}->{itemsPerPage}
        }
    );
}

sub dummy {
	my ($client, $callback, $args) = @_;

	$log->info("Dummy clicked!");
}

1;
