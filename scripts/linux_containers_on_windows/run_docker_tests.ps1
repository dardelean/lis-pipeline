$ErrorActionPreference = "Stop"
$GOPATH_BUILD_DIR=$args[0]
$DOCKER_TESTS_GIT_REPO=$args[1]
$DOCKER_TESTS_GIT_BRANCH=$args[2]
$SMB_SHARE_PATH=$args[3]
$SMB_SHARE_USER=$args[4]
$SMB_SHARE_PASS=$args[5]
$DOCKER_CLIENT_PATH=$args[6]

$LINUX_CONTAINERS_PATH="C:\Program Files\Linux Containers"

function Register-DockerdService {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$build_path
    )

    $env:LCOW_SUPPORTED = "1"
    #$env:LCOW_API_PLATFORM_IF_OMITTED = "linux"
    $env:DOCKER_DEFAULT_PLATFORM="linux"
    Write-Host $env:LCOW_SUPPORTED
    Write-Host $env:LCOW_API_PLATFORM_IF_OMITTED

    if (Test-Path "c:\lcow" ) { 
        Remove-Item "c:\lcow" -Force -Recurse
        New-Item "c:\lcow" -ItemType Directory
    } else {
        New-Item "c:\lcow" -ItemType Directory
    }

    cd $build_path\docker\bundles\
    try {
        New-Service -Name "dockerd" -BinaryPathName `
        "C:\service_wrapper.exe dockerd $build_path\docker\bundles\dockerd.exe -D --experimental --data-root C:\lcow"

        Write-Host "Docker service registration ran successfully"
    } catch {
        Write-Host "Cannot start Docker service"
        Exit 1
    }
}

function Start-DockerdService {
    Start-Service dockerd

    $service = Get-Service dockerd
    if ($service.Status -ne 'Running') {
        Write-Host "Dockerd service not running"
        Exit 1
    } else {
        Write-Host "Dockerd service started successfully"
    }
}

function Start-DockerTests {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$client_path,
        [Parameter(Mandatory=$true)]
        [string]$build_path
    )

    cd $build_path
    $env:PATH +="$client_path"
    Write-Host $env:PATH

    cd docker_tests
    ./runTests.ps1 yes

    Write-Host "Docker tests ran successfully"

    # this is needed for Jenkins archiveArtifacts
    try {
        if (!(Test-Path "${env:WORKSPACE}\\results")) {
            New-Item "${env:WORKSPACE}\\results" -ItemType Directory
        }
        Copy-Item -Path .\tests.json -Destination "${env:WORKSPACE}\\results\\"
        Copy-Item -Path .\tests.log -Destination "${env:WORKSPACE}\\results\\"
    } catch {
        Write-Host "Could not copy the logs to the workspace dir!"
    }
}

function Copy-Artifacts {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$artifact_path,
        [Parameter(Mandatory=$true)]
        [string]$destination
    )

    if (Test-Path $destination) { 
        Get-ChildItem -Path $destination -Include *.* -File -Recurse | foreach { $_.Delete()}
    } else {
        Write-Host "Directory $destination does not exist, we try to create it."
        New-Item $destination -ItemType Directory -ErrorAction SilentlyContinue
    }

    cd $artifact_path
    $initrd_root_dir = Get-ChildItem -Directory | Where-Object {$_.Name.contains("kernel")} | sort -Descending -Property CreationTime | select -first 1
    Copy-Item "$initrd_root_dir\initrd_artifact\initrd.img" $destination -Force
    if ($LASTEXITCODE) {
        throw "Cannot copy $initrd_root_dir\initrd_artifact\initrd.img to $destination"
    } else {
        Write-Host "Initrd artifact copied from $initrd_root_dir\initrd_artifact\initrd.img to $destination successfully"
    }

    Copy-Item "$initrd_root_dir\bootx64.efi" $destination -Force
    if ($LASTEXITCODE) {
        throw "Cannot copy $initrd_root_dir\bootx64.efi to $destination"
    } else {
        Write-Host "bootx64.efi artifact copied from $initrd_root_dir\bootx64.efi to $destination successfully"
    }
    Write-Host "Artifact copied successfully"
}

function Clean-Up {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$build_path
    )

    if (Get-Service dockerd -ErrorAction SilentlyContinue) {
        Stop-Service dockerd
        sc.exe delete dockerd
    }
}

function Mount-Share {
    param(
        [String] $SharedStoragePath,
        [String] $ShareUser,
        [String] $SharePassword
    )

    # Note(avladu): Sometimes, SMB mappings enter into an
    # "Unavailable" state and need to be removed, as they cannot be
    # accessed anymore.
    $smbMappingsUnavailable = Get-SmbMapping -RemotePath $SharedStoragePath `
        -ErrorAction SilentlyContinue | Where-Object {$_.Status -eq "Unavailable"}
    if ($smbMappingsUnavailable) {
        foreach ($smbMappingUnavailable in $smbMappingsUnavailable) {
            net use /delete $smbMappingUnavailable.LocalPath
        }
    }

    $mountPoint = $null
    $smbMapping = Get-SmbMapping -RemotePath $SharedStoragePath -ErrorAction SilentlyContinue
    if ($smbMapping) {
        if ($smbMapping.LocalPath -is [array]){
            return $smbMapping.LocalPath[0]
        } else {
            return $smbMapping.LocalPath
        }
    }
    for ([byte]$c = [char]'G'; $c -le [char]'Z'; $c++) {
        $mountPoint = [char]$c + ":"
        try {
            net.exe use $mountPoint $SharedStoragePath /u:"AZURE\$ShareUser" "$SharePassword" | Out-Null
            if ($LASTEXITCODE) {
                throw "Failed to mount share $SharedStoragePath to $mountPoint."
            } else {
                Write-Host "Successfully monted SMB share on $mountPoint"
                return $mountPoint
            }
        } catch {
            Write-Host $_
        }
    }
    if (!$mountPoint) {
        Write-Host $Error[0]
        throw "Failed to mount $SharedStoragePath to $mountPoint"
    }
}

function Publish-ToPowerBI {
    param(
        [String] $DB_CONF_FILE_PATH
    )
    cd "${env:WORKSPACE}\scripts\linux_containers_on_windows\db_parser"
    pip install -r requirements.txt

    Copy-Item -Path "$DB_CONF_FILE_PATH" -Destination .

    python parser.py
    if ($LASTEXITCODE) {
        throw "Could not publish test results to PowerBI"
    } else {
        Write-Host "Test results published successfully to PowerBI"
    }
}

$current_path = (Get-Item -Path ".\" -Verbose).FullName
$current_path = "$current_path\artifacts"

$mount_path = Mount-Share $SMB_SHARE_PATH $SMB_SHARE_USER $SMB_SHARE_PASS
Write-Host "Mount point is: $mount_path"
$artifacts_path = "$mount_path\lcow_builds\"
Write-Host "Mount path is: $artifacts_path"

Clean-Up $GOPATH_BUILD_DIR

Copy-Artifacts $Artifacts_path $LINUX_CONTAINERS_PATH
Copy-Artifacts $artifacts_path $current_path

#cd $GOPATH_BUILD_DIR\docker\bundles\
Register-DockerdService $GOPATH_BUILD_DIR
Start-DockerdService
Start-DockerTests $DOCKER_CLIENT_PATH $GOPATH_BUILD_DIR
