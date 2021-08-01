#Requires -Module invokebuild
param(
    $jekyllversion = '4',
    $servecontainername = 'jekyll-serve'
)
$rootdir = git rev-parse --show-toplevel
task new {
    mkdir docs -ea 0 | out-null
    push-location $rootdir/docs

    #new
    docker run --rm -it --volume="$($PWD):/srv/jekyll" --env JEKYLL_ENV=production jekyll/jekyll:4 jekyll new . --force

    Pop-Location
}

task build {
    if (test-path .\docs) {
        Push-Location $rootdir/docs
        #build
        docker run --rm -it --volume="$($PWD):/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=production jekyll/jekyll:$jekyllversion jekyll build
        Pop-Location
    }
    else {
        throw "You cannot build what does not exist, run invokebuild new first!"
    }
}

task remove stop, {
    icm {docker rm $servecontainername } -ea 0
}

task stop {
    icm {docker stop $servecontainername } -ea 0  
}

task serve stop, remove, {
    if (test-path .\docs) {
        Push-Location $rootdir/docs
        #serve
        docker run -d --name $servecontainername --volume="$($PWD):/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=development -p 4000:4000 jekyll/jekyll:$jekyllversion jekyll serve

        Pop-Location
    }
    else {
        throw "You cannot run what does not exist, run invokebuild new first!"
    }
}

task run serve

task surf {
    Start-Process Chrome "http://localhost:4000"
}

task newpost {
    $df = get-date -Format 'yyyy-MM-dd'
    $postname = read-host -Prompt 'What would you like to bestow upon your very limited social circle today?'
    New-Item "$rootdir/docs/_posts/$df-$($postname.Replace(' ','-').ToLower()).md" | psedit
}

task . serve, surf