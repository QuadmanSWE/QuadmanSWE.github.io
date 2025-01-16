#Requires -Module invokebuild
param(
    [parameter()]$jekyllversion = '4',
    [parameter()]$servecontainername = 'jekyll-serve',
    [parameter()][string]$postname = '',
    [parameter()][int]$cutoffMinutes = 5,
    [switch]$wait
)
$rootdir = git rev-parse --show-toplevel
task proofread {
    $learntospellyoudunce = @("kubernets", "kuberen", "oath", "serer", "challange")
    $spellingmisstakes = gci "$rootdir/docs/_posts/*.md" | % {
        gc $_ | Select-String -Pattern $learntospellyoudunce
    }
    if ($spellingmisstakes) {
        $spellingmisstakes
        throw 'learn to spell you dunce'
    }
}
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
        docker run --rm -it --volume="$($PWD):/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=production jekyll/jekyll:$jekyllversion /bin/sh -c "bundle install && jekyll build"
        Pop-Location
    }
    else {
        throw "You cannot build what does not exist, run invoke-build new first!"
    }
}

task remove stop, {
    icm { docker rm $servecontainername } -ea 0
}

task stop {
    icm { docker stop $servecontainername } -ea 0  
}

task serve stop, remove, {
    if (-not (test-path .\docs)) {
        throw "You cannot run what does not exist, run invokebuild new first!"
    }
    else {
        Push-Location $rootdir/docs
        #serve
        docker run -d --name $servecontainername --volume="$($PWD):/srv/jekyll" --volume="$PWD/vendor/bundle:/usr/local/bundle" --env JEKYLL_ENV=development -p 4000:4000 jekyll/jekyll:$jekyllversion jekyll serve --watch --drafts

        Pop-Location
        $tries = 15;
        while ($wait -and $tries -gt 0) {
            Start-Sleep 5
            try {
                $result = Invoke-WebRequest -Uri "http://localhost:4000"
                if ($result.StatusCode -eq 200) {
                    Write-Host "Server is up"
                    $tries = 0;
                    break;
                }
                else {
                    Throw ("Server is not up")
                }
            }
            catch {
                Write-Host "Server is not up"
                Start-Sleep 5;
                $tries--;
            }            
        }
    }
}

task run serve

task surf {
    Start-Process firefox "http://localhost:4000"
}

task newpost {
    $df = get-date -Format 'yyyy-MM-dd'
    if ($postname -eq '') {
        $postname = read-host -Prompt 'What would you like to bestow upon your very limited social circle today?'
    }
    $postfile = New-Item "$rootdir/docs/_posts/$df-$($postname.Replace(' ','-').ToLower()).md"
    @"
---
title: $postname
published: true
excerpt_separator: <!--more-->
---

Exerpt!

<!--more-->

Content here

"@ | out-file $postfile -Encoding utf8
    code $postfile
}

task importImages {
    if($IsLinux -eq $true) {
        $screenshotdir = Get-Item ~/Pictures
        $prefixToRemove = 'Screenshot from '
    }
    elseif($IsWindows -eq $true) {
        $screenshotdir = Get-Item $env:USERPROFILE\Pictures\Screenshots
        $prefixToRemove = 'Screenshot from '
    }
    if($screenshotdir -ne $null) {
        Get-ChildItem $screenshotdir | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-$cutoffMinutes) } | ForEach-Object {
            $newname = $_.Name.Replace($prefixToRemove,'').Replace(' ','-').ToLower()
            Write-Host "Copying $($_.FullName) to $rootdir/docs/assets/$newname"
            Copy-Item $_.FullName "$rootdir/docs/assets/$newname"
        }
    }
    else {
        Write-Host "Couldn't import any screenshots, check the path [$screenshotdir]"
    }
}
task . proofread, serve, surf