package Plugins::ARDAudiothek::ProtocolHandler;

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

# Protocolhandler for ardaudiothek:// URLS

use strict;

use base qw(Slim::Player::Protocols::HTTPS);

use Slim::Utils::Log;
use Plugins::ARDAudiothek::API;

use constant PLAYLIST_EPISODE_LIMIT => 1000;

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

sub explodePlaylist {
    my ($class, $client, $uri, $callback) = @_;

    if($uri =~ /ardaudiothek:\/\/episode\/[0-9]+/) {
        $callback->([$uri]);
    }
    elsif($uri =~ /ardaudiothek:\/\/(programset|collection)\/[0-9]+/) {
        my $id = _itemIdFromUri($uri);
        my $playlistType = _typeFromUri($uri);

        Plugins::ARDAudiothek::API->getPlaylist(
            sub {
                my $playlist = shift;
                my @episodeUris;

                for my $episode (@{$playlist->{episodes}}) {
                    push(@episodeUris, 'ardaudiothek://episode/' . $episode->{id});
                }

                $callback->([@episodeUris]);
            },{
                id => $id,
                type => $playlistType,
                offset => 0,
                limit => PLAYLIST_EPISODE_LIMIT
            }
        );
    }
    else {
        $callback->([]);
    }
}

sub getMetadataFor {
    my ($class, $client, $uri) = @_;

    # skip everthing what does not the custom uri
    if($uri !~ m/ardaudiothek:\/\/episode\/[0-9]+/) {
        return undef;
    }

    my $episode = Plugins::ARDAudiothek::API->getEpisode(sub {}, {id => _itemIdFromUri($uri)});

    if(not defined $episode) {
        return undef;
    }

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

sub _typeFromUri {
    my $uri = shift;

    my $type = $uri;
    $type =~ s/(ardaudiothek:\/\/)|(\/[0-9]+)//g;

    return $type;
}

1;
