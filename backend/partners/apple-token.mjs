// WebCrypto emits the 64-byte JOSE ES256 signature directly on Workers and Node.
export async function appleToken({keyId,issuer,privateKey,bundleId},time=Date.now()) {
    if(!keyId||!issuer||!privateKey)throw new Error('missing_apple_credentials');
    const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const seconds=Math.floor(time/1000);
    const payload={iss:issuer,iat:seconds,exp:seconds+120,aud:'appstoreconnect-v1'};
    if(bundleId)payload.bid=bundleId;
    const input=b64({alg:'ES256',kid:keyId,typ:'JWT'})+'.'+b64(payload);
    const der=Buffer.from(privateKey.replace(/-----[^-]+-----|\s/g,''),'base64');
    const key=await crypto.subtle.importKey('pkcs8',der,{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
    const signature=await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,new TextEncoder().encode(input));
    if(signature.byteLength!==64)throw new Error('invalid_es256_signature');
    return input+'.'+Buffer.from(signature).toString('base64url');
}
