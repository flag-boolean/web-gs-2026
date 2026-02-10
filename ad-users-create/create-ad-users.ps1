
# ===== КОДИРОВКА: исправление кириллицы =====
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# ===========================================

Import-Module ActiveDirectory

$Password = "xxXX1234"                     
$OU       = "OU=WINDOWS,DC=windows,DC=lab"  
$Domain   = "windows.lab"                     
$Company  = "ООО ФесМедСнаб"

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# ===== Функция парсинга ФИО (Фамилия Имя Отчество) =====
function Parse-FIO {
    param([string]$FullName)
    
    $parts = $FullName -split '\s+'
    if ($parts.Count -lt 2) { 
        Write-Warning "Некорректный формат ФИО: $FullName"
        return $null 
    }
    
    [PSCustomObject]@{
        Surname    = $parts[0]                                  # Фамилия
        GivenName  = $parts[1]                                  # Имя
        Initials   = if ($parts.Count -ge 3) { "$($parts[2][0])." } else { $null }  # Отчество → инициал (В.)
        DisplayName = $FullName                                 # Полное ФИО
        Name       = "$($parts[0]) $($parts[1])"                # Фамилия Имя
    }
}

# ===== ШАГ 1: Генеральный директор =====
$GenDirFIO = Parse-FIO "Сидоров Пётр Васильевич"

if (-not (Get-ADUser -Filter "SamAccountName -eq 'pvsidorov'" -ErrorAction SilentlyContinue)) {
    $params = @{
        Name                 = $GenDirFIO.Name
        DisplayName          = $GenDirFIO.DisplayName
        GivenName            = $GenDirFIO.GivenName
        Surname              = $GenDirFIO.Surname
        Initials             = $GenDirFIO.Initials
        SamAccountName       = "pvsidorov"
        UserPrincipalName    = "pvsidorov@$Domain"
        AccountPassword      = $SecurePassword
        ChangePasswordAtLogon = $false
        Enabled              = $true
        Path                 = $OU
        Company              = $Company
        Title                = "Генеральный директор"
        Office               = "Главный офис"
        EmailAddress         = "pvsidorov@$Domain"
        PassThru             = $true
    }

    New-ADUser @params | Out-Null
    Write-Host "✓ Генеральный директор: $($GenDirFIO.DisplayName) — $($GenDirFIO.Title)" -ForegroundColor Magenta
}

# ===== ШАГ 2: Список отделов =====
$Departments = @(
    # Административный департамент
    @{ Name = "Отдел IT"; HeadLogin = "dskuznetsov"; HeadFIO = "Кузнецов Дмитрий Сергеевич"; EmpLogin = "mipetrov"; EmpFIO = "Петров Михаил Иванович" }
    @{ Name = "Отдел закупок"; HeadLogin = "afpetrov"; HeadFIO = "Петров Алексей Федорович"; EmpLogin = "sasidorov"; EmpFIO = "Сидоров Сергей Александрович" }
    @{ Name = "Кадровая служба"; HeadLogin = "anpopov"; HeadFIO = "Попов Андрей Николаевич"; EmpLogin = "vvsokolov"; EmpFIO = "Соколов Виктор Васильевич" }
    @{ Name = "Финансовый отдел"; HeadLogin = "epvasilev"; HeadFIO = "Васильев Евгений Петрович"; EmpLogin = "akmorozov"; EmpFIO = "Морозов Андрей Константинович" }
    @{ Name = "Юридический отдел"; HeadLogin = "iamorozov"; HeadFIO = "Морозов Иван Александрович"; EmpLogin = "mksmirnov"; EmpFIO = "Смирнов Максим Константинович" }
    @{ Name = "Служба безопасности"; HeadLogin = "pgsokolov"; HeadFIO = "Соколов Павел Геннадьевич"; EmpLogin = "nvpavlov"; EmpFIO = "Павлов Николай Васильевич" }
    @{ Name = "Отдел защиты активов, СБ"; HeadLogin = "amvolkov"; HeadFIO = "Волков Артём Михайлович"; EmpLogin = "kzaitsev"; EmpFIO = "Зайцев Кирилл Эдуардович" }
    @{ Name = "Отдел охраны труда, СБ"; HeadLogin = "rvorlov"; HeadFIO = "Орлов Роман Валерьевич"; EmpLogin = "apetrov"; EmpFIO = "Петров Артём Петрович" }
    
    # Департамент продаж
    @{ Name = "Отдел сбыта"; HeadLogin = "eatitov"; HeadFIO = "Титов Евгений Алексеевич"; EmpLogin = "nvolkov"; EmpFIO = "Волков Никита Олегович" }
    @{ Name = "Отдел маркетинга"; HeadLogin = "dpzaitseva"; HeadFIO = "Зайцева Дарья Павловна"; EmpLogin = "ivivanov"; EmpFIO = "Иванов Иван Васильевич" }
    @{ Name = "Отдел логистики"; HeadLogin = "evvasileva"; HeadFIO = "Васильева Екатерина Дмитриевна"; EmpLogin = "mksidorov"; EmpFIO = "Сидоров Михаил Константинович" }
    
    # Производственный департамент
    @{ Name = "Отдел качества и технического контроля"; HeadLogin = "iamorozov2"; HeadFIO = "Морозов Иван Александрович"; EmpLogin = "rsmorozov"; EmpFIO = "Морозов Роман Сергеевич" }
    @{ Name = "Инженерный отдел"; HeadLogin = "pgsokolov2"; HeadFIO = "Соколов Павел Геннадьевич"; EmpLogin = "mvsokolov"; EmpFIO = "Соколов Максим Васильевич" }
    @{ Name = "Отдел по обслуживанию и ТП"; HeadLogin = "rvorlov2"; HeadFIO = "Орлов Роман Валерьевич"; EmpLogin = "pvmorozov"; EmpFIO = "Морозов Павел Викторович" }
)

# ===== ШАГ 3: Создаём начальников отделов =====
foreach ($Dept in $Departments) {
    $HeadFIO = Parse-FIO $Dept.HeadFIO
    
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Dept.HeadLogin)'" -ErrorAction SilentlyContinue)) {
        $params = @{
            Name                 = $HeadFIO.Name
            DisplayName          = $HeadFIO.DisplayName
            GivenName            = $HeadFIO.GivenName
            Surname              = $HeadFIO.Surname
            Initials             = $HeadFIO.Initials
            SamAccountName       = $Dept.HeadLogin
            UserPrincipalName    = "$($Dept.HeadLogin)@$Domain"
            AccountPassword      = $SecurePassword
            ChangePasswordAtLogon = $false
            Enabled              = $true
            Path                 = $OU
            Company              = $Company
            Title                = "Начальник отдела"
            Manager              = "pvsidorov"
            Office               = "Главный офис"
            EmailAddress         = "$($Dept.HeadLogin)@$Domain"
            PassThru             = $true
        }

        New-ADUser @params | Out-Null
        Write-Host "✓ Начальник $($Dept.Name): $($HeadFIO.DisplayName) → Сидоров П.В." -ForegroundColor Cyan
    }
}

# ===== ШАГ 4: Создаём сотрудников отделов =====
foreach ($Dept in $Departments) {
    $EmpFIO = Parse-FIO $Dept.EmpFIO
    
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Dept.EmpLogin)'" -ErrorAction SilentlyContinue)) {
        $params = @{
            Name                 = $EmpFIO.Name
            DisplayName          = $EmpFIO.DisplayName
            GivenName            = $EmpFIO.GivenName
            Surname              = $EmpFIO.Surname
            Initials             = $EmpFIO.Initials
            SamAccountName       = $Dept.EmpLogin
            UserPrincipalName    = "$($Dept.EmpLogin)@$Domain"
            AccountPassword      = $SecurePassword
            ChangePasswordAtLogon = $false
            Enabled              = $true
            Path                 = $OU
            Company              = $Company
            Title                = "Специалист"
            Manager              = $Dept.HeadLogin
            Office               = "Главный офис"
            EmailAddress         = "$($Dept.EmpLogin)@$Domain"
            PassThru             = $true
        }

        New-ADUser @params | Out-Null
        Write-Host "✓ Сотрудник $($Dept.Name): $($EmpFIO.DisplayName) → $($HeadFIO.DisplayName)" -ForegroundColor Green
    }
}

Write-Host "`n✅ Создано: 1 ген.дир + 14 начальников + 14 сотрудников = 29 пользователей" -ForegroundColor Yellow
Write-Host "ℹ️  ФИО заполнены через атрибуты: GivenName (имя), Surname (фамилия), Initials (инициал отчества)" -ForegroundColor White
