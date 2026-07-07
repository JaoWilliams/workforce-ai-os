import {NextIntlClientProvider} from 'next-intl';
import {getMessages} from 'next-intl/server';

export const metadata = {
  title: 'WORKFORCE AI OS',
  description: 'Plataforma de gestion de fuerza laboral',
};

export default async function LocaleLayout({children, params: {locale}}) {
  const messages = await getMessages();

  return (
    <html lang={locale}>
      <body>
        <NextIntlClientProvider messages={messages}>
          {children}
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
