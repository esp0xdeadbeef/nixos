{ ramGiB, extraGiB ? 8 }:

"${toString (ramGiB + extraGiB)}G"
