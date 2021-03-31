package Plugins::ARDAudiothek::ProtocolHandler;

# Pseudohandler for ardaudiothek:// URLS

use strict;

use Slim::Utils::Log;
use Plugins::ARDAudiothek::Plugin;
use Plugins::ARDAudiothek::API;

my $log = logger('plugin.ardaudiothek');

sub overridePlayback {
    my ($class, $client, $url) = @_;

    my $id = _itemIdFromUrl($url);

    Plugins::ARDAudiothek::API->getItem(
        sub {
            my $episode = Plugins::ARDAudiothek::Plugin::episodeDetails(shift);
            my $image = Plugins::ARDAudiothek::Plugin::selectImageFormat($episode->{image});
            my @items;
            
            # the following is a bit hacky, but it works. Thanks to:
            # https://forums.slimdevices.com/showthread.php?104357-Playlist-addition-in-overridePlayback-function&highlight=Protocol+Handler+ProtocolHandler
            # https://forums.slimdevices.com/showthread.php?106039-how-does-metadata-(artwork)-update-works-for-players&p=860790&viewfull=1#post860790
            push @items, Slim::Schema->updateOrCreate({ 
                    url => $episode->{url}
                }
            );
            
            $client->execute([ 'playlist', 'clear' ]);
	        $client->execute([ 'playlist', 'addtracks', 'listRef', \@items ]);
	        $client->execute([ 'play' ]);

            $client->playingSong->pluginData( wmaMeta => {
                    icon => $image,
                    cover => $image,
                    title => $episode->{title},
                    artitst => $episode->{show},
                    album => $episode->{show},
                    description => $episode->{description}
                }
            );

            Slim::Control::Request::notifyFromArray( $client, ['newmetadata']);

            $log->info($image);
        },{
            id => $id
        }
    );

    return 1;
}

sub canDirectStream { 
    return 1;
}

sub contentType {
    return 'mp3';
}

sub isRemote { 1 }

sub _itemIdFromUrl {
    my $url = shift;
    
    my $id = $url;
    $id =~ s/ardaudiothek:\/\///;
    
    return $id;
}

1;
