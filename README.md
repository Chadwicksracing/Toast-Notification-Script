# Toast Notification Script - Mofified by Chad Brower

    2.0.0 -   Huge changes to how this script handles custom protocols
                - Added Support for Software Updates : Searches for an update (IPU) and will store in variable
                - Added Support for Custom Actions/Protocols within the script under user context removing the need for that to be run under SYSTEM/ADMIN : Only Supports SoftwareUpdate right now
                    <Option Name="Action" Value="ToastRunUpdateID:" />
                - Added Support to dynamically create Custom Action Scripts to support Custom Protocols : Only Supports Software Updates right now
                - Added New XML Types for SoftwareUpdates : 
                    <Option Name="RunUpdateTitle" Enabled="True" Value="Version 1909" />
                    <Option Name="RunUpdateID" Enabled="True" Value="3012973" />
                - Removed Custom Protocols Folder : Future Support for that will be within the script
                - Removed MSI / Zip files

Orginally From:
Current version: 1.8.0
Download the complete Windows 10 Toast Notification Script: https://github.com/imabdk/Toast-Notification-Script/blob/master/ToastNotificationScript1.8.0.zip

Blog posts, documentation as well as if any questions, please use: https://www.imab.dk/windows-10-toast-notification-script/
