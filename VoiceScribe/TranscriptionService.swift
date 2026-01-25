import Foundation

enum TranscriptionError: Error, LocalizedError {
    case serverNotAvailable
    case networkError(Error)
    case invalidResponse
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotAvailable:
            return "Transcription server is not available"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

class TranscriptionService {
    private let baseURL = "http://127.0.0.1:8765"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // 2 minutes for transcription
        config.timeoutIntervalForResource = 300  // 5 minutes total
        session = URLSession(configuration: config)
    }

    func checkHealth(completion: @escaping (Bool, Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/health") else {
            completion(false, false)
            return
        }

        let task = session.dataTask(with: url) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, false)
                return
            }

            let status = json["status"] as? String == "ok"
            let modelLoaded = json["model_loaded"] as? Bool ?? false
            completion(status, modelLoaded)
        }

        task.resume()
    }

    func transcribe(audioURL: URL, completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        guard let url = URL(string: "\(baseURL)/transcribe") else {
            completion(.failure(.serverNotAvailable))
            return
        }

        // Read audio file data
        guard let audioData = try? Data(contentsOf: audioURL) else {
            completion(.failure(.transcriptionFailed("Could not read audio file")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = audioData
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let errorMsg = json["error"] as? String, !errorMsg.isEmpty {
                        completion(.failure(.transcriptionFailed(errorMsg)))
                        return
                    }

                    if let text = json["text"] as? String {
                        completion(.success(text))
                        return
                    }
                }

                completion(.failure(.invalidResponse))
            } catch {
                completion(.failure(.networkError(error)))
            }
        }

        task.resume()
    }

    func transcribeFile(path: String, completion: @escaping (Result<String, TranscriptionError>) -> Void) {
        guard let url = URL(string: "\(baseURL)/transcribe-file") else {
            completion(.failure(.serverNotAvailable))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["path": path]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let errorMsg = json["error"] as? String, !errorMsg.isEmpty {
                        completion(.failure(.transcriptionFailed(errorMsg)))
                        return
                    }

                    if let text = json["text"] as? String {
                        completion(.success(text))
                        return
                    }
                }

                completion(.failure(.invalidResponse))
            } catch {
                completion(.failure(.networkError(error)))
            }
        }

        task.resume()
    }
}
