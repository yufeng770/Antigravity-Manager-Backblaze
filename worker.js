export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.headers.get('X-Backup-Secret') !== env.AUTH_SECRET) {
      return new Response('Unauthorized', { status: 401 });
    }
    if (request.method === 'GET' && url.pathname === '/download') {
      const object = await env.BACKUP_BUCKET.get('backup.tar.gz');
      return object
        ? new Response(object.body, { headers: { 'Content-Type': 'application/gzip' } })
        : new Response('Not found', { status: 404 });
    }
    if (request.method === 'PUT' && url.pathname === '/upload') {
      await env.BACKUP_BUCKET.put('backup.tar.gz', request.body);
      return new Response('ok');
    }
    return new Response('Not found', { status: 404 });
  }
};
