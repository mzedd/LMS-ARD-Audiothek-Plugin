package Plugins::ARDAudiothek::ProtocolHandler;

# Protocolhandler for ardaudiothek:// URLS

use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::API;

my $log = logger('plugin.ardaudiothek');

sub scanUrl {
    my ($class, $uri, $args) = @_;
    my $id = _itemIdFromUri($uri);

    Plugins::ARDAudiothek::API->getEpisode(sub{
            my $episode = shift;
            my $url = $episode->{url};

            Slim::Utils::Scanner::Remote->scanURL($url, $args);

            my $client = $args->{client}->master;
            my $image = Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl});

            $client->playingSong->pluginData( wmaMeta => {
                    icon   => $image,
                    cover  => $image,
                    artist => $episode->{show},
                    title  => $episode->{title}
                }
            );

            Slim::Control::Request::notifyFromArray( $client, [ 'newmetadata' ] );
        },{
            id => $id
        }
    );

    return;
}

sub getMetadataFor {
    my ($class, $client, $uri) = @_;

    my $episode = Plugins::ARDAudiothek::API::getEpisodeFromCache(_itemIdFromUri($uri)); 
    my $image = Plugins::ARDAudiothek::API::selectImageFormat($episode->{imageUrl});

    return {
        icon => $image,
        cover => $image,
        title => $episode->{title},
        artist => $episode->{show},
        duration => $episode->{duration},
        description => $episode->{description}
    };
}

sub _itemIdFromUri {
    my $uri = shift;
    
    my $id = $uri;
    $id =~ s/\D//g;
    
    return $id;
}

1;
