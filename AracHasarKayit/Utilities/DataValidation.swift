import Foundation

// MARK: - Validation Error

enum ValidationError: Error, LocalizedError {
    case emptyField(String)
    case invalidFormat(String)
    case outOfRange(String, min: Any, max: Any)
    case tooShort(String, minLength: Int)
    case tooLong(String, maxLength: Int)
    case invalidSwissPlate
    case invalidEmail
    case invalidPhoneNumber
    case futureDate(String)
    case pastDate(String)
    case duplicateValue(String)
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "\(field) cannot be empty"
        case .invalidFormat(let field):
            return "\(field) has invalid format"
        case .outOfRange(let field, let min, let max):
            return "\(field) must be between \(min) and \(max)"
        case .tooShort(let field, let minLength):
            return "\(field) must be at least \(minLength) characters"
        case .tooLong(let field, let maxLength):
            return "\(field) cannot exceed \(maxLength) characters"
        case .invalidSwissPlate:
            return "Invalid Swiss license plate format"
        case .invalidEmail:
            return "Invalid email address"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        case .futureDate(let field):
            return "\(field) cannot be in the future"
        case .pastDate(let field):
            return "\(field) cannot be in the past"
        case .duplicateValue(let field):
            return "\(field) already exists"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Data Validator Protocol

protocol DataValidator {
    func validate() throws
}

// MARK: - String Validators

extension String {
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return predicate.evaluate(with: self)
    }
    
    var isValidSwissPlate: Bool {
        // Swiss plates: ZH 123456 or ZH 123 (canton code + numbers)
        let plateRegex = "^[A-Z]{1,2}\\s*\\d{1,6}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", plateRegex)
        let cleaned = self.replacingOccurrences(of: " ", with: "").uppercased()
        return predicate.evaluate(with: cleaned)
    }
    
    var isValidPhoneNumber: Bool {
        // Swiss phone: +41 XX XXX XX XX or 0XX XXX XX XX
        let phoneRegex = "^(\\+41|0)[0-9]{9,10}$"
        let cleaned = self.replacingOccurrences(of: " ", with: "")
        let predicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return predicate.evaluate(with: cleaned)
    }
    
    func validate(fieldName: String, minLength: Int? = nil, maxLength: Int? = nil) throws {
        // Check empty
        if self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyField(fieldName)
        }
        
        // Check min length
        if let min = minLength, self.count < min {
            throw ValidationError.tooShort(fieldName, minLength: min)
        }
        
        // Check max length
        if let max = maxLength, self.count > max {
            throw ValidationError.tooLong(fieldName, maxLength: max)
        }
    }
}

// MARK: - Arac Validation

extension Arac: DataValidator {
    func validate() throws {
        // Validate plate
        try plaka.validate(fieldName: "License Plate", minLength: 2, maxLength: 10)
        if !plaka.isValidSwissPlate {
            throw ValidationError.invalidSwissPlate
        }
        
        // Validate brand
        try marka.validate(fieldName: "Brand", minLength: 2, maxLength: 50)
        
        // Validate model
        try model.validate(fieldName: "Model", minLength: 1, maxLength: 50)
        
        // Validate category
        try kategori.validate(fieldName: "Category", minLength: 1, maxLength: 5)
        
        // Validate QR code
        try qrCode.validate(fieldName: "QR Code", minLength: 1)
        
        // Validate spare key count
        if spareKeyCount < 0 || spareKeyCount > 10 {
            throw ValidationError.outOfRange("Spare Key Count", min: 0, max: 10)
        }
        
        // Validate registration date
        if kayitTarihi > Date() {
            throw ValidationError.futureDate("Registration Date")
        }
        
        print("✅ Vehicle validation passed: \(plakaFormatli)")
    }
}

// MARK: - HasarKaydi Validation

extension HasarKaydi: DataValidator {
    func validate() throws {
        // Validate RES code: accept both \"12345\" and \"RES-12345\" formats,
        // but require that the numeric part is valid (1–8 digits).
        let cleanedRes = Validators.cleanResCode(resKodu)
        guard Validators.validateResCode(cleanedRes) else {
            throw ValidationError.invalidFormat("RES Code")
        }
        
        // Validate kilometers
        if km < 0 || km > 1_000_000 {
            throw ValidationError.outOfRange("Kilometers", min: 0, max: 1_000_000)
        }
        
        // Validate dates
        if tarih > Date() {
            throw ValidationError.futureDate("Damage Date")
        }
        
        if handoverTarihi > Date() {
            throw ValidationError.futureDate("Handover Date")
        }
        
        if handoverTarihi < tarih {
            throw ValidationError.custom("Handover date cannot be before damage date")
        }
        
        // Validate photos (at least 1 photo required)
        if fotograflar.isEmpty {
            throw ValidationError.custom("At least one photo is required")
        }
        
        if fotograflar.count > 20 {
            throw ValidationError.custom("Maximum 20 photos allowed")
        }
        
        print("✅ Damage validation passed: \(resKodu)")
    }
}

// MARK: - ServisFirma Validation

extension ServisFirma: DataValidator {
    func validate() throws {
        // Validate name
        try ad.validate(fieldName: "Company Name", minLength: 2, maxLength: 100)
        
        // Validate phone
        if !telefon.isEmpty {
            try telefon.validate(fieldName: "Phone", minLength: 5, maxLength: 20)
        }
        
        // Validate email
        if !email.isEmpty && !email.isValidEmail {
            throw ValidationError.invalidEmail
        }
        
        // Validate address
        try adres.validate(fieldName: "Address", minLength: 5, maxLength: 200)
        
        print("✅ Service company validation passed: \(ad)")
    }
}

// MARK: - IadeIslemi Validation

extension IadeIslemi: DataValidator {
    func validate() throws {
        // Validate plate
        try aracPlaka.validate(fieldName: "Vehicle Plate", minLength: 2)
        
        // Validate return date
        if iadeTarihi > Date() {
            throw ValidationError.futureDate("Return Date")
        }
        
        // Validate photos
        if fotograflar.isEmpty {
            throw ValidationError.custom("At least one photo is required for return")
        }
        
        print("✅ Return validation passed: \(aracPlaka)")
    }
}

// MARK: - OfficeOperation Validation

extension OfficeOperation: DataValidator {
    func validate() throws {
        // Validate amount
        if amount < 0 {
            throw ValidationError.outOfRange("Amount", min: 0, max: Double.infinity)
        }
        
        if amount > 1_000_000 {
            throw ValidationError.custom("Amount seems unreasonably high. Please verify.")
        }
        
        // Validate date
        if date > Date() {
            throw ValidationError.futureDate("Operation Date")
        }
        
        // Type-specific validations
        switch type {
        case .posClosing:
            if let count = posCount, count <= 0 {
                throw ValidationError.custom("POS count must be greater than 0")
            }
            
            if let amounts = posAmounts {
                if amounts.isEmpty {
                    throw ValidationError.custom("POS amounts cannot be empty")
                }
                
                let totalPOS = amounts.reduce(0, +)
                if abs(totalPOS - amount) > 0.01 {
                    throw ValidationError.custom("Sum of POS amounts (\(totalPOS)) doesn't match total amount (\(amount))")
                }
            }
            
        case .fuelReceipt, .washing:
            if let plate = vehiclePlate {
                try plate.validate(fieldName: "Vehicle Plate", minLength: 2)
            }
            
        default:
            break
        }
        
        // Validate photos
        if photos.isEmpty {
            throw ValidationError.custom("At least one photo/receipt is required")
        }
        
        print("✅ Office operation validation passed: \(type.rawValue)")
    }
}

// MARK: - Activity Validation

extension Activity: DataValidator {
    func validate() throws {
        // Validate description
        try aciklama.validate(fieldName: "Description", minLength: 3, maxLength: 200)
        
        // Validate date
        if tarih > Date() {
            throw ValidationError.futureDate("Activity Date")
        }
        
        // Validate user info
        if kullaniciAdi == nil && kullaniciEmail == nil {
            throw ValidationError.custom("Either user name or email must be provided")
        }
        
        if let email = kullaniciEmail, !email.isValidEmail {
            throw ValidationError.invalidEmail
        }
        
        print("✅ Activity validation passed")
    }
}
