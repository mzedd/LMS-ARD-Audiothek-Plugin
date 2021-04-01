package Plugins::ARDAudiothek::ProtocolHandler;

# Pseudohandler for ardaudiothek:// URLS

use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::Plugin;
use Plugins::ARDAudiothek::API;

my $log = logger('plugin.ardaudiothek');

sub scanUrl {
    my ($class, $uri, $args) = @_;

    $log->info($uri);

    my $id = _itemIdFromUri($uri);

    Plugins::ARDAudiothek::API->getItem(sub{
            my $episode = Plugins::ARDAudiothek::Plugin::episodeDetails(shift);

            my $url = $episode->{url};
           
            Slim::Utils::Scanner::Remote->scanURL($url, $args);
        },{
            id => $id
        }
    );

    return;
}

sub explodePlaylist {
    my ($class, $client, $uri, $callback) = @_;

    if($uri =~ /ardaudiothek:\/\/episode\/[0-9]+/) {
        $callback->([$uri]);
    }
    elsif($uri =~ /ardaudiothek:\/\/programset\/[0-9]+/) {
        my $id = _itemIdFromUri($uri);

        $log->info("moin");

        Plugins::ARDAudiothek::API->getProgramSet(
            sub {
                my $content = shift;
                my @episodeUris;

                for my $episode (@{$content->{_embedded}->{"mt:items"}}) {
                    push(@episodeUris, 'ardaudiothek://episode/' . $episode->{id});
                }
                
                $log->info(Data::Dump::dump(@episodeUris));

                $callback->([@episodeUris]);
            },{
                programSetID => $id,
                offset => 0,
                limit => 100
            }
        );
    } 
    elsif($uri =~ /ardaudiothek:\/\/collection\/[0-9]+/) {
        $callback->([]);
    }
    else {
        $callback->([]);
    }
}

sub _itemIdFromUri {
    my $uri = shift;
    
    my $id = $uri;
    $id =~ s/\D//g;
    
    return $id;
}

1;
