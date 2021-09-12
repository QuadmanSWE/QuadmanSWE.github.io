param(
    $chartname
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
            Move-Item -Path $_ -Destination $chartpublishdestination
        }
    } 
}
task copy publish

task . lint, package, publish
