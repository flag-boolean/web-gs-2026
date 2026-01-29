Import-Module ActiveDirectory

$Password = "TestPass123!"                     
$OU       = "OU=TestUsers,DC=domain,DC=local"  
$Domain   = "test.local"                     
$Company  = "Тестовая компания"

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

# ===== ШАГ 1: Генеральный директор (единый для всех) =====
$GenDir = @{
    Login = "pvsidorov"  # Сидоров Пётр Васильевич
    Title = "Генеральный директор"
}

if (-not (Get-ADUser -Filter "SamAccountName -eq '$($GenDir.Login)'" -ErrorAction SilentlyContinue)) {
    New-ADUser `
        -Name $GenDir.Login `
        -SamAccountName $GenDir.Login `
        -UserPrincipalName "$($GenDir.Login)@$Domain" `
        -AccountPassword $SecurePassword `
        -ChangePasswordAtLogon $false `
        -Enabled $true `
        -Path $OU `
        -Company $Company `
        -Title $GenDir.Title `
        -Office "Главный офис" `
        -EmailAddress "$($GenDir.Login)@$Domain" `
        -PassThru | Out-Null
    
    Write-Host "✓ Генеральный директор: $($GenDir.Login) — $($GenDir.Title)" -ForegroundColor Magenta
}

# ===== ШАГ 2: Список отделов с УНИКАЛЬНЫМИ логинами (начальники ≠ сотрудники) =====
$Departments = @(
    # Административный департамент
    @{ Name = "Отдел IT"; HeadLogin = "dskuznetsov"; HeadName = "Кузнецов Дмитрий Сергеевич"; EmpLogin = "mipetrov"; EmpName = "Петров Михаил Иванович" }
    @{ Name = "Отдел закупок"; HeadLogin = "afpetrov"; HeadName = "Петров Алексей Федорович"; EmpLogin = "sasidorov"; EmpName = "Сидоров Сергей Александрович" }
    @{ Name = "Кадровая служба"; HeadLogin = "anpopov"; HeadName = "Попов Андрей Николаевич"; EmpLogin = "vvsokolov"; EmpName = "Соколов Виктор Васильевич" }
    @{ Name = "Финансовый отдел"; HeadLogin = "epvasilev"; HeadName = "Васильев Евгений Петрович"; EmpLogin = "akmorozov"; EmpName = "Морозов Андрей Константинович" }
    @{ Name = "Юридический отдел"; HeadLogin = "iamorozov"; HeadName = "Морозов Иван Александрович"; EmpLogin = "mksmirnov"; EmpName = "Смирнов Максим Константинович" }
    @{ Name = "Служба безопасности"; HeadLogin = "pgsokolov"; HeadName = "Соколов Павел Геннадьевич"; EmpLogin = "nvpavlov"; EmpName = "Павлов Николай Васильевич" }
    @{ Name = "Отдел защиты активов, СБ"; HeadLogin = "amvolkov"; HeadName = "Волков Артём Михайлович"; EmpLogin = "kzaitsev"; EmpName = "Зайцев Кирилл Эдуардович" }
    @{ Name = "Отдел охраны труда, СБ"; HeadLogin = "rvorlov"; HeadName = "Орлов Роман Валерьевич"; EmpLogin = "apetrov"; EmpName = "Петров Артём Петрович" }
    
    # Департамент продаж
    @{ Name = "Отдел сбыта"; HeadLogin = "eatitov"; HeadName = "Титов Евгений Алексеевич"; EmpLogin = "nvolkov"; EmpName = "Волков Никита Олегович" }
    @{ Name = "Отдел маркетинга"; HeadLogin = "dpzaitseva"; HeadName = "Зайцева Дарья Павловна"; EmpLogin = "ivivanov"; EmpName = "Иванов Иван Васильевич" }
    @{ Name = "Отдел логистики"; HeadLogin = "evvasileva"; HeadName = "Васильева Екатерина Дмитриевна"; EmpLogin = "mksidorov"; EmpName = "Сидоров Михаил Константинович" }
    
    # Производственный департамент
    @{ Name = "Отдел качества и технического контроля"; HeadLogin = "iamorozov2"; HeadName = "Морозов Иван Александрович"; EmpLogin = "rsmorozov"; EmpName = "Морозов Роман Сергеевич" }
    @{ Name = "Инженерный отдел"; HeadLogin = "pgsokolov2"; HeadName = "Соколов Павел Геннадьевич"; EmpLogin = "mvsokolov"; EmpName = "Соколов Максим Васильевич" }
    @{ Name = "Отдел по обслуживанию и ТП"; HeadLogin = "rvorlov2"; HeadName = "Орлов Роман Валерьевич"; EmpLogin = "pvmorozov"; EmpName = "Морозов Павел Викторович" }
)

# ===== ШАГ 3: Создаём начальников отделов (подчиняются генеральному директору) =====
foreach ($Dept in $Departments) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Dept.HeadLogin)'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name $Dept.HeadLogin `
            -SamAccountName $Dept.HeadLogin `
            -UserPrincipalName "$($Dept.HeadLogin)@$Domain" `
            -AccountPassword $SecurePassword `
            -ChangePasswordAtLogon $false `
            -Enabled $true `
            -Path $OU `
            -Company $Company `
            -Title "Начальник отдела" `
            -Manager $GenDir.Login `
            -Office "Главный офис" `
            -EmailAddress "$($Dept.HeadLogin)@$Domain" `
            -PassThru | Out-Null

        Write-Host "✓ Начальник $($Dept.Name): $($Dept.HeadLogin) → $($GenDir.Login)" -ForegroundColor Cyan
    }
}

# ===== ШАГ 4: Создаём сотрудников отделов (подчиняются начальникам) =====
foreach ($Dept in $Departments) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($Dept.EmpLogin)'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name $Dept.EmpLogin `
            -SamAccountName $Dept.EmpLogin `
            -UserPrincipalName "$($Dept.EmpLogin)@$Domain" `
            -AccountPassword $SecurePassword `
            -ChangePasswordAtLogon $false `
            -Enabled $true `
            -Path $OU `
            -Company $Company `
            -Title "Специалист" `
            -Manager $Dept.HeadLogin `
            -Office "Главный офис" `
            -EmailAddress "$($Dept.EmpLogin)@$Domain" `
            -PassThru | Out-Null

        Write-Host "✓ Сотрудник $($Dept.Name): $($Dept.EmpLogin) → $($Dept.HeadLogin)" -ForegroundColor Green
    }
}

Write-Host "`n✅ Создано: 1 ген.дир + 14 начальников + 14 сотрудников = 29 пользователей" -ForegroundColor Yellow