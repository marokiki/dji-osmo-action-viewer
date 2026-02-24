import AVFoundation

enum PlayerItemFactory {
    static func makeAsset(for recording: Recording) async -> AVAsset {
        guard recording.segmentURLs.count > 1 else {
            return AVURLAsset(url: recording.segmentURLs[0])
        }

        let composition = AVMutableComposition()
        var cursor = CMTime.zero

        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        for (index, url) in recording.segmentURLs.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration)) ?? .zero
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
                try? compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: cursor)
                if index == 0 {
                    if let transform = try? await videoTrack.load(.preferredTransform) {
                        compositionVideoTrack?.preferredTransform = transform
                    }
                }
            }

            if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
                try? compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        return composition
    }
}
