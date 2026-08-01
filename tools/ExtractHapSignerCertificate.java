import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.ohos.hapsigntool.hap.verify.VerifyHap;
import com.ohos.hapsigntool.hap.verify.VerifyResult;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cms.SignerInformation;
import org.bouncycastle.util.Store;

public final class ExtractHapSignerCertificate {
    @SuppressWarnings({"rawtypes", "unchecked"})
    public static void main(String[] args) throws Exception {
        if (args.length != 5) {
            throw new IllegalArgumentException(
                "Usage: ExtractHapSignerCertificate <hap> <profile-certificate> "
                    + "<signer-certificate> <profile-spki> <signer-spki>");
        }

        VerifyResult result = new VerifyHap().verifyHap(args[0]);
        if (!result.isVerified()) {
            throw new IllegalStateException("HAP verification failed: " + result.getMessage());
        }

        List<SignerInformation> signerInfos = result.getSignerInfos();
        Store<X509CertificateHolder> certificates = result.getCertificateHolderStore();
        if (signerInfos == null || signerInfos.isEmpty() || certificates == null) {
            throw new IllegalStateException("Verified HAP did not expose signer information.");
        }

        Map<String, X509CertificateHolder> signerCertificates = new LinkedHashMap<>();
        for (SignerInformation signerInfo : signerInfos) {
            for (Object match : certificates.getMatches(signerInfo.getSID())) {
                if (!(match instanceof X509CertificateHolder)) {
                    throw new IllegalStateException("HAP signer certificate has an unexpected type.");
                }
                X509CertificateHolder certificate = (X509CertificateHolder) match;
                signerCertificates.put(
                    Base64.getEncoder().encodeToString(certificate.getEncoded()), certificate);
            }
        }

        if (signerCertificates.size() != 1) {
            throw new IllegalStateException(
                "Expected exactly one HAP signer certificate, found "
                    + signerCertificates.size() + ".");
        }

        X509CertificateHolder signerCertificate = signerCertificates.values().iterator().next();
        X509Certificate profileCertificate;
        try (InputStream input = Files.newInputStream(Paths.get(args[1]))) {
            profileCertificate = (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(input);
        }

        Files.write(Paths.get(args[2]), signerCertificate.getEncoded());
        Files.write(Paths.get(args[3]), profileCertificate.getPublicKey().getEncoded());
        Files.write(Paths.get(args[4]), signerCertificate.getSubjectPublicKeyInfo().getEncoded());
    }
}
