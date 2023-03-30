import Foundation
import ArgumentParser
import ZipArchive


extension String {
    func matches(pattern: String) -> Bool {
        return range(of: pattern, options: .regularExpression) != nil
    }
    
    func isValidFileName() -> Bool {
        let invalidCharacters = CharacterSet(charactersIn: #"\/:*?"<>|"#)
        return self.rangeOfCharacter(from: invalidCharacters) == nil
    }
    
    func replacingInvalidFilenameCharacters() -> String {
        let invalidCharactersArray: [Character] = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
        var newString = self
        for c in invalidCharactersArray {
            let invalidString = String(c)
            let fullwidthString = invalidString.applyingTransform(.fullwidthToHalfwidth, reverse: true) ?? invalidString
            newString = newString.replacingOccurrences(of: invalidString, with: fullwidthString)
        }
        return newString
    }
}

extension FileManager {
    func createTempDirectory() throws -> String {
        let tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        return tempDirectory
    }
}

struct Jipper: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a password-protected zip file with Shift-JIS-encoded filenames.")
    
    @Argument(help: "The directory to zip.")
    var inputDirectory: String
    
    @Option(name: .shortAndLong, help: "The password to encrypt the zip file.")
    var password: String?
    
    @Option(name: .shortAndLong, help: "The length of the password to generate.")
    var lengthOfPassword: Int?
    
    func run() throws {
        let fileManager = FileManager.default
        
        // Check if input directory exists
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: inputDirectory, isDirectory: &isDirectory) {
            print("Input directory does not exist.")
            return
        }
        
        if !isDirectory.boolValue {
            print("Input path is not a directory.")
            return
        }
        
        // Create temporary directory for encoded files
        let tempDirPath = try FileManager().createTempDirectory()
        try fileManager.createDirectory(atPath: tempDirPath, withIntermediateDirectories: true, attributes: nil)
        
        // Get list of files in input directory and move to encoded directory
        let excludedPaths = ["*.DS_Store", "__MACOSX"]
        let files = try fileManager.contentsOfDirectory(atPath: inputDirectory)
        for file in files {
            print("file = \(file)")
            let filePath = inputDirectory.appending("/\(file)")
            let attributes = try fileManager.attributesOfItem(atPath: filePath)
            let fileType = attributes[.type] as? FileAttributeType
            
            if fileType == .typeRegular {
                if !excludedPaths.contains(where: { file.matches(pattern: $0) }) {
                    let encodedFile = file.replacingInvalidFilenameCharacters().data(using: .shiftJIS).flatMap { String(data: $0, encoding: .shiftJIS) }
                    let encodedFilePath = tempDirPath.appending("/\(encodedFile!)")
                    try fileManager.copyItem(atPath: filePath, toPath: encodedFilePath)
                }
            } else if fileType == .typeDirectory {
                let subDirectory = inputDirectory.appending("/\(file)")
                if !excludedPaths.contains(where: { file.matches(pattern: $0) }) {
                    let encodedSubDirectory = file.replacingInvalidFilenameCharacters().data(using: .shiftJIS).flatMap { String(data: $0, encoding: .shiftJIS) }
                    let tempSubDirectoryPath = tempDirPath.appending("/\(encodedSubDirectory!)")
                    try fileManager.createDirectory(atPath: tempSubDirectoryPath, withIntermediateDirectories: true, attributes: nil)
                    
                    let subFiles = try fileManager.contentsOfDirectory(atPath: subDirectory)
                    for subFile in subFiles {
                        let subFilePath = subDirectory.appending("/\(subFile)")
                        let subAttributes = try fileManager.attributesOfItem(atPath: subFilePath)
                        let subFileType = subAttributes[.type] as? FileAttributeType
                        
                        if subFileType == .typeRegular {
                            if !excludedPaths.contains(where: { subFile.matches(pattern: $0) }) {
                                let encodedSubFile = subFile.replacingInvalidFilenameCharacters().data(using: .shiftJIS).flatMap { String(data: $0, encoding: .shiftJIS) }
                                let encodedSubFilePath = tempSubDirectoryPath.appending("/\(encodedSubFile!)")
                                try fileManager.copyItem(atPath: subFilePath, toPath: encodedSubFilePath)
                            }
                        }
                    }
                }
            }
        }
        
        // Create zip file and encrypt zip file with password if provided
        print("creating zip file...")
        let zipFilePath = inputDirectory.appending(".zip")
        let encodedZipFilePath = tempDirPath.appending(".zip")
        
        if let password = password {
            try SSZipArchive.createZipFile(atPath: encodedZipFilePath, withContentsOfDirectory: tempDirPath, withPassword: password)
        } else if let passwordLength = lengthOfPassword {
            let generatedPassword = generatePassword(length: passwordLength)
            try SSZipArchive.createZipFile(atPath: encodedZipFilePath, withContentsOfDirectory: tempDirPath, withPassword: generatedPassword)
            print("Generated password: \(generatedPassword)")
        } else {
            try SSZipArchive.createZipFile(atPath: encodedZipFilePath, withContentsOfDirectory: tempDirPath)
        }
        
        // Move zip file to input directory
        try fileManager.moveItem(atPath: encodedZipFilePath, toPath: zipFilePath)
        
        // Delete temporary directory
        try fileManager.removeItem(atPath: tempDirPath)
        
        func generatePassword(length: Int) -> String {
            let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-="
            return String((0..<length).map{ _ in characters.randomElement()! })
        }
    }
}

Jipper.main()
