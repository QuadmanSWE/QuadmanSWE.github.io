#Requires -Module invokebuild
<#
.SYNOPSIS
    wrapper for helm using invoke-build tasks
.DESCRIPTION
    Can be used to create, lint, and package helm charts as well as publish them by copying and merging the repo in the dir exposed in github pages.
.EXAMPLE
    PS C:\> invoke-build new -chartname 'mychart'
    Creates a new helm chart named mychart in the helm directory
.EXAMPLE
    PS C:\> invoke-build -chartname 'qr'
    Lints, packages, and publishes the qr helm chart so that the tarball and index.yaml can be committed to the repo and thus upon merge to main be public.
.EXAMPLE
    PS C:\> invoke-build -url "http://localhost:4000/helm-charts"
    Publishes the helm repo with the url as it shows up when serving jekyll for debug in docker
.PARAMETER chartname
    Name of the chart to act on, required for new, for other none means all
.PARAMETER url
    The url to use in the index.yaml, useful when debugging and not publishing to the blog.
#>
param(
    $chartname,
    $url = "https://blog.dsoderlund.com/helm-charts"
)
$rootdir = git rev-parse --show-toplevel
$chartsource = "$rootdir/helm/charts"
$chartpublishdestination = "$rootdir/docs/helm-charts"
[string[]]$chartnames;
if ($null -eq $chartname) {
    $chartnames = Get-ChildItem $chartsource -Directory | Select-Object -ExpandProperty FullName
}
else {
    $chartnames = $chartname
}

task new {
    if ($null -eq $chartname) {
        throw ('you must supply a $chartname if you want to create this way')
    }
    else {
        helm create "$chartsource/$chartname"
    }
}

task lint {
    $chartnames | ForEach-Object {
        exec {
            helm lint $_
        }
    }    
}
task package {
    $chartnames | ForEach-Object {
        exec {
            helm package $_
        }
    } 
}
task build package

task publish {
    if (!(test-path $chartpublishdestination)) {
        mkdir $chartpublishdestination | out-null
    }
    if ($null -eq $chartname) {
        $tarballs = Get-ChildItem "$rootdir/helm" -Filter '*.tgz'
    }
    else {
        $tarballs = Get-ChildItem "$rootdir/helm" -Filter '*.tgz' | Where-Object { $_.BaseName -like "$chartname-*" }
    }
    $tarballs | ForEach-Object {
        exec {
            Move-Item -Path $_ -Destination $chartpublishdestination -Force
        }
    }
    exec {
        helm repo index --merge index.yaml --url $url $chartpublishdestination
        remove-item index.yaml #we don't need this extra temp file
    }
}
task copy publish

task . lint, package, publish
