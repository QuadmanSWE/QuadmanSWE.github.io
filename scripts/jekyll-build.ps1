# This scripts runs the jekyll builder on docker
# I use this on windows 10 with wsl2 and docker desktop.

mkdir vendor/bundle -ea 0 | out-null

docker run --rm -it --volume="$($PWD):/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=production jekyll/jekyll:4 jekyll build
