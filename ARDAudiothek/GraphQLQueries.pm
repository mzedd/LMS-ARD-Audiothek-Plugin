package Plugins::ARDAudiothek::GraphQLQueries;

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

use constant {
    DISCOVER =>
    '{
      homescreen {
        sections {
          nodes {
            id
            ... on Item {
              id
              synopsis
              title
              duration
              image {
                url
              }
              audios {
                url
              }
              programSet {
                title
              }
            }
            ... on ProgramSet {
              id
              title
              image {
                url
              }
            }
            ... on EditorialCollection {
              id
              image {
                url
              }
              title
            }
          }
        }
      }
    }',

    EDITORIAL_CATEGORIES => 
    '{
      editorialCategories {
        nodes {
          id
          title
          image {
            url
          }
        }
      }
    }',

    EDITORIAL_CATEGORY_PLAYLISTS =>
    '{
      editorialCategory(id: $id) {
        sections {
          nodes {
            ... on Item {
              id
              title
              duration
              synopsis
              image {
                url
              }
              audios {
                url
              }
              programSet {
                title
              }
            }
            ... on ProgramSet {
              id
              title
              image {
                url
              }
            }
          }
        }
      }
    }',

    PROGRAM_SET => 
    '{
      programSet(id: $id) {
        id
        title
        numberOfElements
        items {
          nodes {
            audios {
              url
            }
            image {
              url
            }
            id
            synopsis
            title
            duration
          }
        }
      }
    }', 

    EPISODE =>
    '{
      item(id: $id) {
        id
        audios {
          url
        }
        duration
        image {
          url
        }
        programSet {
          title
        }
        title
        synopsis
      }
    }'
};

1;
