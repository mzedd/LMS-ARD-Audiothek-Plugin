package Plugins::ARDAudiothek::ProtocolHandler;

# Pseudohandler for ardaudiothek:// URLS

use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::Plugin;
use Plugins::ARDAudiothek::API;

my $log = logger('plugin.ardaudiothek');

sub scanUrl {
    my ($class, $url, $args) = @_;

    my $id = _itemIdFromUrl($url);

    Plugins::ARDAudiothek::API->getItem(sub{
            my $episode = Plugins::ARDAudiothek::Plugin::episodeDetails(shift);

            $url = $episode->{url};
           
            Slim::Utils::Scanner::Remote->scanURL($url, $args);
        },{
            id => $id
        }
    );

    return;
}

sub _itemIdFromUrl {
    my $url = shift;
    
    my $id = $url;
    $id =~ s/\D//g;
    
    return $id;
}

1;
